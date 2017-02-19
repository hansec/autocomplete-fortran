from __future__ import print_function
import re
import json
import sys
from optparse import OptionParser
#
parser = OptionParser()
parser.add_option("-s", "--std",
                  action="store_true", dest="std", default=False,
                  help="Read file from STDIN")
parser.add_option("-d", "--debug",
                  action="store_true", dest="debug", default=False,
                  help="Print debug information")
parser.add_option("-p", "--pretty",
                  action="store_true", dest="pretty", default=False,
                  help="Format JSON output")
parser.add_option("--close_scopes",
                  action="store_true", dest="close_scopes", default=False,
                  help="Force all open scopes to close at end of parsing")
parser.add_option("--fixed",
                  action="store_true", dest="fixed", default=False,
                  help="Parse using fixed-format rules")
parser.add_option("--files", dest="files", default=None,
                  help="Files to parse")
(options, args) = parser.parse_args()
debug = options.debug
fixed_format = options.fixed
#
USE_REGEX = re.compile(r'[ \t]*USE[ \t]*([a-z0-9_]*)', re.I)
SUB_REGEX = re.compile(r'[ \t]*(PURE|ELEMENTAL|RECURSIVE)*[ \t]*(SUBROUTINE)', re.I)
END_SUB_REGEX = re.compile(r'[ \t]*END[ \t]*SUBROUTINE', re.I)
FUN_REGEX = re.compile(r'[ \t]*(PURE|ELEMENTAL|RECURSIVE)*[ \t]*(FUNCTION)', re.I)
RESULT_REGEX = re.compile(r'RESULT[ ]*\(([a-z0-9_]*)\)', re.I)
END_FUN_REGEX = re.compile(r'[ \t]*END[ \t]*FUNCTION', re.I)
MOD_REGEX = re.compile(r'[ \t]*MODULE[ \t]*([a-z0-9_]*)', re.I)
END_MOD_REGEX = re.compile(r'[ \t]*END[ \t]*MODULE', re.I)
PROG_REGEX = re.compile(r'[ \t]*PROGRAM[ \t]*([a-z0-9_]*)', re.I)
END_PROG_REGEX = re.compile(r'[ \t]*END[ \t]*PROGRAM', re.I)
INT_REGEX = re.compile(r'[ \t]*(?:ABSTRACT)?[ \t]*INTERFACE[ \t]*([a-z0-9_]*)', re.I)
END_INT_REGEX = re.compile(r'[ \t]*END[ \t]*INTERFACE', re.I)
END_GEN_REGEX = re.compile(r'[ \t]*END[ \t]*$', re.I)
TYPE_DEF_REGEX = re.compile(r'[ \t]*TYPE', re.I)
EXTENDS_REGEX = re.compile(r'EXTENDS[ ]*\(([a-z0-9_]*)\)', re.I)
END_TYPED_REGEX = re.compile(r'[ \t]*END[ \t]*TYPE', re.I)
NAT_VAR_REGEX = re.compile(r'[ \t]*(INTEGER|REAL|DOUBLE PRECISION|COMPLEX|CHARACTER|LOGICAL|PROCEDURE|CLASS|TYPE)', re.I)
KIND_SPEC_REGEX = re.compile(r'([ \t]*\([a-z0-9_ =*]*\)|\*[0-9]*)', re.I)
KEYWORD_LIST_REGEX = re.compile(r'[ \t]*,[ \t]*(PUBLIC|PRIVATE|ALLOCATABLE|POINTER|TARGET|DIMENSION\([a-z0-9_:, ]*\)|OPTIONAL|INTENT\([inout]*\)|DEFERRED|NOPASS|SAVE|PARAMETER)', re.I)
TATTR_LIST_REGEX = re.compile(r'[ \t]*,[ \t]*(PUBLIC|PRIVATE|ABSTRACT|EXTENDS\([a-z0-9_]*\))', re.I)
VIS_REGEX = re.compile(r'(PUBLIC|PRIVATE)', re.I)
WORD_REGEX = re.compile(r'[a-z][a-z0-9_]*', re.I)
SUB_PAREN_MATCH = re.compile(r'\([a-z0-9_, ]*\)', re.I)
KIND_SPEC_MATCH = re.compile(r'\([a-z0-9_, =*]*\)', re.I)
#
if fixed_format:
    COMMENT_LINE_MATCH = re.compile(r'(!|c|d|\*)')
    CONT_REGEX = re.compile(r'(     [\S])')
else:
    COMMENT_LINE_MATCH = re.compile(r'([ \t]*!)')
    CONT_REGEX = re.compile(r'([ \t]*&)')
#
def separate_def_list(test_str):
    paren_count=0
    def_list = []
    curr_str = ''
    for char in test_str:
        if char == '(':
            paren_count += 1
        elif char == ')':
            paren_count -= 1
        elif char == ',' and paren_count==0:
            if curr_str != '':
                def_list.append(curr_str)
                curr_str = ''
            continue
        curr_str += char
    if curr_str != '':
        def_list.append(curr_str)
    return def_list
#
def get_var_dims(test_str):
    paren_count = 0
    curr_dim = 0
    for char in test_str:
        if char == '(':
            paren_count += 1
            if paren_count==1:
                curr_dim = 1
        elif char == ')':
            paren_count -= 1
        elif char == ',' and paren_count==1:
            curr_dim += 1
    return curr_dim
#
def parse_keywords(keywords):
    modifiers = []
    for key in keywords:
        key_lower = key.lower()
        if key_lower == 'pointer':
            modifiers.append(1)
        elif key_lower == 'allocatable':
            modifiers.append(2)
        elif key_lower == 'optional':
            modifiers.append(3)
        elif key_lower == 'public':
            modifiers.append(4)
        elif key_lower == 'private':
            modifiers.append(5)
        elif key_lower == 'nopass':
            modifiers.append(6)
        elif key_lower.startswith('dimension'):
            ndims = key_lower.count(':')
            modifiers.append(20+ndims)
    modifiers.sort()
    return modifiers
#
def read_var_def(line, type_word=None):
    if type_word is None:
        type_match = NAT_VAR_REGEX.match(line)
        if type_match is None:
            return None
        else:
            type_word = type_match.group(0).strip()
            trailing_line = line[type_match.end(0):]
    else:
        trailing_line = line[len(type_word):]
    type_word = type_word.upper()
    trailing_line = trailing_line.split('!')[0]
    #
    kind_match = KIND_SPEC_REGEX.match(trailing_line)
    if kind_match is not None:
        type_word += kind_match.group(0).strip().lower()
        trailing_line = trailing_line[kind_match.end(0):]
    else:
        # Class and Type statements need a kind spec
        if type_word.lower() == 'class' or type_word.lower() == 'type':
            return None
        # Make sure next character is space or comma
        if trailing_line[0] != ' ' and trailing_line[0] != ',':
            return None
    #
    keyword_match = KEYWORD_LIST_REGEX.match(trailing_line)
    keywords = []
    while (keyword_match is not None):
        keywords.append(keyword_match.group(0).replace(',',' ').strip().upper())
        trailing_line = trailing_line[keyword_match.end(0):]
        keyword_match = KEYWORD_LIST_REGEX.match(trailing_line)
    # Check if function
    fun_def = read_fun_def(trailing_line, [type_word, keywords])
    if fun_def is not None:
        return fun_def
    #
    line_split = trailing_line.split('::')
    if len(line_split) == 1:
        if len(keywords) > 0:
            return None
        else:
            trailing_line = line_split[0]
    else:
        trailing_line = line_split[1]
    #
    var_words = separate_def_list(trailing_line.strip())
    #
    return 'var', [type_word, keywords, var_words]
#
def read_fun_def(line, return_type=None):
    fun_match = FUN_REGEX.match(line)
    if fun_match is None:
        return None
    #
    trailing_line = line[fun_match.end(0):].strip()
    trailing_line = trailing_line.split('!')[0]
    name_match = WORD_REGEX.match(trailing_line)
    if name_match is not None:
        name = name_match.group(0)
        trailing_line = trailing_line[name_match.end(0):].strip()
    else:
        return None
    #
    paren_match = SUB_PAREN_MATCH.match(trailing_line)
    if paren_match is not None:
        word_match = WORD_REGEX.findall(paren_match.group(0))
        if word_match is not None:
            word_match = [word for word in word_match]
            args = ','.join(word_match)
        trailing_line = trailing_line[paren_match.end(0):]
    #
    return_var = None
    if return_type is None:
        trailing_line = trailing_line.strip()
        results_match = RESULT_REGEX.match(trailing_line)
        if results_match is not None:
            return_var = results_match.group(1).strip().lower()
    return 'fun', [name, args, [return_type, return_var]]
#
def read_sub_def(line):
    sub_match = SUB_REGEX.match(line)
    if sub_match is None:
        return None
    #
    trailing_line = line[sub_match.end(0):].strip()
    trailing_line = trailing_line.split('!')[0]
    name_match = WORD_REGEX.match(trailing_line)
    if name_match is not None:
        name = name_match.group(0)
        trailing_line = trailing_line[name_match.end(0):].strip()
    else:
        return None
    #
    paren_match = SUB_PAREN_MATCH.match(trailing_line)
    args = ''
    if paren_match is not None:
        word_match = WORD_REGEX.findall(paren_match.group(0))
        if word_match is not None:
            word_match = [word for word in word_match]
            args = ','.join(word_match)
        trailing_line = trailing_line[paren_match.end(0):]
    return 'sub', [name, args]
#
def read_type_def(line):
    type_match = TYPE_DEF_REGEX.match(line)
    if type_match is None:
        return None
    trailing_line = line[type_match.end(0):]
    trailing_line = trailing_line.split('!')[0]
    # Parse keywords
    keyword_match = TATTR_LIST_REGEX.match(trailing_line)
    keywords = []
    parent = None
    while (keyword_match is not None):
        keyword_strip = keyword_match.group(0).replace(',',' ').strip().upper()
        extend_match = EXTENDS_REGEX.match(keyword_strip)
        if extend_match is not None:
            parent = extend_match.group(1).lower()
        else:
            keywords.append(keyword_strip)
        #
        trailing_line = trailing_line[keyword_match.end(0):]
        keyword_match = TATTR_LIST_REGEX.match(trailing_line)
    # Get name
    line_split = trailing_line.split('::')
    if len(line_split) == 1:
        if len(keywords) > 0 and parent is None:
            return None
        else:
            if trailing_line.split('(')[0].strip().lower() == 'is':
                return None
            trailing_line = line_split[0]
    else:
        trailing_line = line_split[1]
    #
    word_match = WORD_REGEX.match(trailing_line.strip())
    if word_match is not None:
        name = word_match.group(0)
    else:
        return None
    #
    return 'typ', [name, parent, keywords]
#
def read_mod_def(line):
    mod_match = MOD_REGEX.match(line)
    if mod_match is None:
        return None
    else:
        name = mod_match.group(1)
        if name.lower() == 'procedure':
            trailing_line = line[mod_match.end(1):]
            pro_names = []
            line_split = trailing_line.split(',')
            for name in line_split:
                pro_names.append(name.strip().lower())
            return 'int_pro', pro_names
        return 'mod', name
#
def read_prog_def(line):
    prog_match = PROG_REGEX.match(line)
    if prog_match is None:
        return None
    else:
        return 'prog', prog_match.group(1)
#
def read_int_def(line):
    int_match = INT_REGEX.match(line)
    if int_match is None:
        return None
    else:
        int_name = int_match.group(1).lower()
        if int_name == '':
            return None
        if int_name == 'assignment' or int_name == 'operator':
            return None
        return 'int', int_match.group(1)
#
def read_use_stmt(line):
    use_match = USE_REGEX.match(line)
    if use_match is None:
        return None
    else:
        trailing_line = line[use_match.end(0):].lower()
        use_mod = use_match.group(1)
        only_ind = trailing_line.find('only:')
        only_list = []
        if only_ind > -1:
            only_split = trailing_line[only_ind+5:].split(',')
            for only_stmt in only_split:
                only_list.append(only_stmt.split('=>')[0].strip())
        return 'use', [use_mod, only_list]
#
class fortran_scope:
    def __init__(self, line_number, name, enc_scope=None, args=None):
        self.sline = line_number
        self.eline = None
        self.name = name
        self.children = []
        self.use = []
        self.parent = None
        self.vis = 0
        self.args = args
        if enc_scope is not None:
            self.FQSN = enc_scope.lower() + "::" + self.name.lower()
        else:
            self.FQSN = self.name.lower()
    def set_visibility(self, new_vis):
        self.vis = new_vis
    def add_use(self, use_mod, only_list=[]):
        lower_only = []
        for only in only_list:
            lower_only.append(only.lower())
        self.use.append([use_mod.lower(), lower_only])
    def set_parent(self, parent_type):
        self.parent = parent_type
    def add_child(self,child):
        self.children.append(child)
    def get_type(self):
        return -1
    def get_desc(self):
        return 'unknown'
    def is_optional(self):
        return False
    def end(self, line_number):
        self.eline = line_number
    def write_scope(self):
        scope_dict = {'name': self.name, 'type': self.get_type(), 'desc': self.get_desc(), 'fbound': [self.sline, self.eline], 'mem': []}#{}}
        if self.args is not None:
            arg_str = self.args
            if len(self.children) > 0:
                args_split = arg_str.split(',')
                for child in self.children:
                    try:
                        ind = args_split.index(child.name)
                    except:
                        continue
                    if child.is_optional():
                        args_split[ind] = args_split[ind] + "=" + args_split[ind]
                arg_str = ",".join(args_split)
            scope_dict['args'] = arg_str
        if len(self.children) > 0:
            for child in self.children:
                scope_dict['mem'].append(child.name.lower())
        if len(self.use) > 0:
            scope_dict['use'] = []
            for use_stmt in self.use:
                scope_dict['use'].append(use_stmt)
        if self.parent is not None:
            scope_dict['parent'] = self.parent
        if self.vis == -1:
            scope_dict['vis'] = '-1'
        elif self.vis == 1:
            scope_dict['vis'] = '1'
        return scope_dict
#
class fortran_module(fortran_scope):
    def __init__(self, line_number, name, enc_scope=None, args=None):
        self.sline = line_number
        self.eline = None
        self.name = name
        self.children = []
        self.use = []
        self.parent = None
        self.vis = 0
        self.args = args
        if enc_scope is not None:
            self.FQSN = enc_scope.lower() + "::" + self.name.lower()
        else:
            self.FQSN = self.name.lower()
    def get_type(self):
        return 1
    def get_desc(self):
        return 'MODULE'
#
class fortran_program(fortran_scope):
    def __init__(self, line_number, name, enc_scope=None, args=None):
        self.sline = line_number
        self.eline = None
        self.name = name
        self.children = []
        self.use = []
        self.parent = None
        self.vis = 0
        self.args = args
        if enc_scope is not None:
            self.FQSN = enc_scope.lower() + "::" + self.name.lower()
        else:
            self.FQSN = self.name.lower()
    def get_type(self):
        return 1
    def get_desc(self):
        return 'PROGRAM'
#
class fortran_subroutine(fortran_scope):
    def __init__(self, line_number, name, enc_scope=None, args=None):
        self.sline = line_number
        self.eline = None
        self.name = name
        self.children = []
        self.use = []
        self.parent = None
        self.vis = 0
        self.args = args
        if enc_scope is not None:
            self.FQSN = enc_scope.lower() + "::" + self.name.lower()
        else:
            self.FQSN = self.name.lower()
    def get_type(self):
        return 2
    def get_desc(self):
        return 'SUBROUTINE'
#
class fortran_function(fortran_scope):
    def __init__(self, line_number, name, enc_scope=None, args=None, return_type=None, result_var=None):
        self.sline = line_number
        self.eline = None
        self.name = name
        self.children = []
        self.use = []
        self.result_var = result_var
        if return_type is not None:
            self.return_type = return_type[0]
            self.modifiers = parse_keywords(return_type[1])
        else:
            self.return_type = None
            self.modifiers = []
        self.parent = None
        self.vis = 0
        self.args = args
        if enc_scope is not None:
            self.FQSN = enc_scope.lower() + "::" + self.name.lower()
        else:
            self.FQSN = self.name.lower()
    def get_type(self):
        return 3
    def get_desc(self):
        desc = None
        if self.result_var is not None:
            result_var_lower = self.result_var.lower()
            for child in self.children:
                if child.name == result_var_lower:
                    return child.get_desc()
        if self.return_type is not None:
            return self.return_type
        return 'FUNCTION'
#
class fortran_type(fortran_scope):
    def __init__(self, line_number, name, modifiers, enc_scope=None, args=None):
        self.sline = line_number
        self.eline = None
        self.name = name
        self.children = []
        self.use = []
        self.modifiers = modifiers
        self.parent = None
        self.vis = 0
        self.args = args
        if enc_scope is not None:
            self.FQSN = enc_scope.lower() + "::" + self.name.lower()
        else:
            self.FQSN = self.name.lower()
        for modifier in self.modifiers:
            if modifier == 4:
                self.vis = 1
            elif modifier == 5:
                self.vis = -1
    def get_type(self):
        return 4
    def get_desc(self):
        return 'TYPE'
#
class fortran_int(fortran_scope):
    def __init__(self, line_number, name, enc_scope=None, args=None):
        self.sline = line_number
        self.eline = None
        self.name = name
        self.children = []
        self.use = []
        self.parent = None
        self.vis = 0
        self.args = args
        if enc_scope is not None:
            self.FQSN = enc_scope.lower() + "::" + self.name.lower()
        else:
            self.FQSN = self.name.lower()
    def add_child(self, child_fqn):
        self.children.append(child_fqn)
    def get_type(self):
        return 5
    def get_desc(self):
        return 'INTERFACE'
    def write_scope(self):
        child_list = []
        for child in self.children:
            child_list.append(child.lower())
        scope_dict = {'name': self.name, 'type': 7, 'fbound': [self.sline, self.eline], 'mem': child_list}
        if self.vis == -1:
            scope_dict['vis'] = '-1'
        elif self.vis == 1:
            scope_dict['vis'] = '1'
        return scope_dict
#
class fortran_obj:
    def __init__(self, line_number, name, var_desc, modifiers, enc_scope=None, link_obj=None):
        self.sline = line_number
        self.name = name
        self.desc = var_desc
        self.modifiers = modifiers
        self.children = []
        self.vis = 0
        if link_obj is not None:
            self.link_obj = link_obj.lower()
        else:
            self.link_obj = None
        if enc_scope is not None:
            self.FQSN = enc_scope.lower() + "::" + self.name.lower()
        else:
            self.FQSN = self.name.lower()
        for modifier in self.modifiers:
            if modifier == 4:
                self.vis = 1
            elif modifier == 5:
                self.vis = -1
    def set_visibility(self, new_vis):
        self.vis = new_vis
    def get_type(self):
        return 6
    def get_desc(self):
        return self.desc
    def set_dim(self,ndim):
        for (i,modifier) in enumerate(self.modifiers):
            if modifier > 20:
                self.modifiers[i] = ndim+20
                return
        self.modifiers.append(ndim+20)
    def is_optional(self):
        try:
            ind = self.modifiers.index(3)
        except:
            return False
        return True
    def write_scope(self):
        scope_dict = {'name': self.name, 'type': self.get_type(), 'fdef': self.sline, 'desc': self.get_desc()}
        if self.vis == -1:
            scope_dict['vis'] = '-1'
        elif self.vis == 1:
            scope_dict['vis'] = '1'
        if self.link_obj is not None:
            scope_dict['link'] = self.link_obj
        if len(self.modifiers) > 0:
            scope_dict['mods'] = self.modifiers
        return scope_dict
#
class fortran_file:
    def __init__(self, indent_level=None):
        self.global_dict = {}
        self.scope_list = []
        self.variable_list = []
        self.public_list = []
        self.private_list = []
        self.scope_stack = []
        self.end_stack = []
        self.current_scope = None
        self.END_REGEX = None
        self.enc_scope_name = None
        self.indent_level = indent_level
    def get_enc_scope_name(self):
        if self.current_scope is None:
            return None
        name_str = self.current_scope.name
        if len(self.scope_stack) > 0:
            for scope in reversed(self.scope_stack):
                name_str = scope.name + '::' + name_str
        return name_str
    def add_scope(self,new_scope, END_SCOPE_REGEX, hidden=False):
        if hidden:
            self.variable_list.append(new_scope)
        else:
            self.scope_list.append(new_scope)
        if self.current_scope is not None:
            self.current_scope.add_child(new_scope)
            self.scope_stack.append(self.current_scope)
        if self.END_REGEX is not None:
            self.end_stack.append(self.END_REGEX)
        self.current_scope = new_scope
        self.END_REGEX = END_SCOPE_REGEX
        self.enc_scope_name = self.get_enc_scope_name()
    def end_scope(self,line_number):
        self.current_scope.end(line_number)
        if len(self.scope_stack) > 0:
            self.current_scope = self.scope_stack.pop()
        else:
            self.current_scope = None
        if len(self.end_stack) > 0:
            self.END_REGEX = self.end_stack.pop()
        else:
            self.END_REGEX = None
        self.enc_scope_name = self.get_enc_scope_name()
    def add_variable(self,new_var):
        self.current_scope.add_child(new_var)
        self.variable_list.append(new_var)
    def add_int_member(self,key):
        self.current_scope.add_child(key)
    def add_private(self,name):
        self.private_list.append(self.enc_scope_name+'::'+name)
    def add_public(self,name):
        self.public_list.append(self.enc_scope_name+'::'+name)
    def add_use(self,mod_words):
        if len(mod_words) > 0:
            n = len(mod_words)
            if n > 2:
                use_list = mod_words[2:]
                self.current_scope.add_use(mod_words[0], use_list)
            else:
                self.current_scope.add_use(mod_words[0])
    def dump_json(self, line_count, close_open=False):
        if (self.current_scope is not None) and (not close_open):
            print(json.dumps({'error': 'Scope stack not empty'}))
            return
        if close_open:
            while (self.current_scope is not None):
                self.end_scope(line_count)
        js_output = {'objs': {}, 'scopes': []}
        for scope in self.scope_list:
            js_output['objs'][scope.FQSN] = scope.write_scope()
            js_output['scopes'].append(scope.FQSN)
        for variable in self.variable_list:
            js_output['objs'][variable.FQSN] = variable.write_scope()
        for private_obj in self.private_list:
            if private_obj in js_output['objs']:
                js_output['objs'][private_obj]['vis'] = -1
        for public_obj in self.public_list:
            if public_obj in js_output['objs']:
                js_output['objs'][public_obj]['vis'] = 1
        print(json.dumps(js_output, indent=self.indent_level, separators=(',', ':')))
#
def_tests = [read_var_def, read_sub_def, read_fun_def, read_type_def, read_use_stmt, read_int_def, read_mod_def, read_prog_def]
#
def process_file(filename,close_open_scopes):
    if filename == 'STDIN':
        f = sys.stdin
        close_open_scopes = True
    else:
        f = open(filename)
    indent_level = None
    if options.pretty:
        indent_level = 2
    file_obj = fortran_file(indent_level)
    line_number = 0
    next_line_num = 1
    at_eof = False
    next_line = None
    while(not at_eof):
        # Get next line
        if next_line is None:
            line = f.readline()
        else:
            line = next_line
            next_line = None
        line_number = next_line_num
        next_line_num = line_number + 1
        if line == '':
            break # Reached end of file
        # Skip comment lines
        match = COMMENT_LINE_MATCH.match(line)
        if (match is not None):
            continue
        # Merge lines with continuations
        if fixed_format:
            next_line = f.readline()
            cont_match = CONT_REGEX.match(next_line)
            while( cont_match is not None ):
                line = line.rstrip() + next_line[6:].strip()
                next_line_num += 1
                next_line = f.readline()
                cont_match = CONT_REGEX.match(next_line)
        else:
            iAmper = line.find('&')
            iComm = line.find('!')
            if iComm < 0:
                iComm = iAmper + 1
            while (iAmper >= 0 and iAmper < iComm):
                split_line = line.split('&')
                next_line = f.readline()
                if next_line == '':
                    at_eof = True
                    break # Reached end of file
                # Skip comment lines
                match = COMMENT_LINE_MATCH.match(next_line)
                if (match is not None):
                    continue
                cont_match = CONT_REGEX.match(next_line)
                if cont_match is not None:
                    next_line = next_line[cont_match.end(0):]
                next_line_num += 1
                line = split_line[0].rstrip() + ' ' + next_line.strip()
                iAmper = line.find('&')
                iComm = line.find('!')
                if iComm < 0:
                    iComm = iAmper + 1
            next_line = None
        line = line.rstrip()
        # Test for scope end
        if file_obj.END_REGEX is not None:
            match = file_obj.END_REGEX.match(line)
            if (match is not None):
                file_obj.end_scope(line_number)
                if(debug):
                    print('{1} !!! END scope({0})'.format(line_number, line.strip()))
                continue
            line_no_comment = line.split('!')[0]
            match = END_GEN_REGEX.match(line_no_comment)
            if (match is not None):
                file_obj.end_scope(line_number)
                if(debug):
                    print('{1} !!! END scope({0})'.format(line_number, line.strip()))
                continue
        # Loop through tests
        obj_read = None
        for test in def_tests:
            obj_read = test(line)
            if obj_read is not None:
                break
        #
        if obj_read is not None:
            obj_type = obj_read[0]
            obj = obj_read[1]
            if obj_type == 'var':
                link_name = None
                if obj[0][:3] == 'PRO':
                    if isinstance(file_obj.current_scope,fortran_int):
                        for var_name in obj[2]:
                            file_obj.add_int_member(var_name)
                        if(debug):
                            print('{1} !!! INTERFACE-PRO statement({0})'.format(line_number, line.strip()))
                        continue
                    i1 = obj[0].find('(')
                    i2 = obj[0].find(')')
                    if i1 > -1 and i2 > -1:
                        link_name = obj[0][i1+1:i2]
                for var_name in obj[2]:
                    if var_name.find('=>') > -1:
                        name_split = var_name.split('=>')
                        name_stripped = name_split[0]
                        link_name = name_split[1].split('(')[0].strip()
                        if link_name.lower() == 'null':
                            link_name = None
                    else:
                        name_stripped = var_name.split('=')[0]
                    var_dim = 0
                    if name_stripped.find('(') > -1:
                        var_dim = get_var_dims(name_stripped)
                    name_stripped = name_stripped.split('(')[0].strip()
                    modifiers = parse_keywords(obj[1])
                    new_var = fortran_obj(line_number, name_stripped, obj[0], modifiers, file_obj.enc_scope_name, link_name)
                    if var_dim > 0:
                        new_var.set_dim(var_dim)
                    file_obj.add_variable(new_var)
                if(debug):
                    print('{1} !!! VARIABLE statement({0})'.format(line_number, line.strip()))
            elif obj_type == 'mod':
                new_mod = fortran_module(line_number, obj, file_obj.enc_scope_name)
                file_obj.add_scope(new_mod, END_MOD_REGEX)
                if(debug):
                    print('{1} !!! MODULE statement({0})'.format(line_number, line.strip()))
            elif obj_type == 'prog':
                new_prog = fortran_program(line_number, obj, file_obj.enc_scope_name)
                file_obj.add_scope(new_prog, END_PROG_REGEX)
                if(debug):
                    print('{1} !!! PROGRAM statement({0})'.format(line_number, line.strip()))
            elif obj_type == 'sub':
                new_sub = fortran_subroutine(line_number, obj[0], file_obj.enc_scope_name, obj[1])
                file_obj.add_scope(new_sub, END_SUB_REGEX)
                if(debug):
                    print('{1} !!! SUBROUTINE statement({0})'.format(line_number, line.strip()))
            elif obj_type == 'fun':
                new_fun = fortran_function(line_number, obj[0], file_obj.enc_scope_name, obj[1], return_type=obj[2][0], result_var=obj[2][1])
                file_obj.add_scope(new_fun, END_FUN_REGEX)
                if obj[2][0] is not None:
                    new_obj = fortran_obj(line_number, obj[0], obj[2][0][0], obj[2][0][1], file_obj.enc_scope_name, None)
                    file_obj.add_variable(new_obj)
                if(debug):
                    print('{1} !!! FUNCTION statement({0})'.format(line_number, line.strip()))
            elif obj_type == 'typ':
                modifiers = parse_keywords(obj[2])
                new_type = fortran_type(line_number, obj[0], modifiers, file_obj.enc_scope_name)
                if obj[1] is not None:
                    new_type.set_parent(obj[1])
                file_obj.add_scope(new_type, END_TYPED_REGEX)
                if(debug):
                    print('{1} !!! TYPE statement({0})'.format(line_number, line.strip()))
            elif obj_type == 'int':
                new_int = fortran_int(line_number, obj, file_obj.enc_scope_name)
                file_obj.add_scope(new_int, END_INT_REGEX, True)
                if(debug):
                    print('{1} !!! INTERFACE statement({0})'.format(line_number, line.strip()))
            elif obj_type == 'int_pro':
                if file_obj.current_scope is None:
                    continue
                if not isinstance(file_obj.current_scope,fortran_int):
                    continue
                for name in obj:
                    file_obj.add_int_member(name)
                if(debug):
                    print('{1} !!! INTERFACE-PRO statement({0})'.format(line_number, line.strip()))
            elif obj_type == 'use':
                file_obj.current_scope.add_use(obj[0], obj[1])
                if(debug):
                    print('{1} !!! USE statement({0})'.format(line_number, line.strip()))
        # Look for visiblity statement
        match = VIS_REGEX.match(line)
        if (match is not None):
            match_lower = match.group(0).lower()
            trailing_line = line[match.end(0):]
            mod_words = WORD_REGEX.findall(trailing_line)
            if len(mod_words) == 0:
                if match_lower == 'private':
                    file_obj.current_scope.set_visibility(-1)
            else:
                if match_lower == 'private':
                    for word in mod_words:
                        file_obj.add_private(word)
                else:
                    for word in mod_words:
                        file_obj.add_public(word)
            if(debug):
                print('Found visiblity statement, {0}:{1}, {2}'.format(filename, line_number, line.strip()))
            continue
    f.close()
    file_obj.dump_json(line_number,close_open_scopes)
#
if options.std:
    files = ['STDIN']
else:
    files = options.files.split(',')
#
for (ifile,fname) in enumerate(files):
    filename = fname
    try:
        process_file(filename,options.close_scopes)
    except:
        if debug:
            raise
        print(json.dumps({'error': 'Python error'}))
