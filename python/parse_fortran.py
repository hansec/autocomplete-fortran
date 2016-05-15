import re
import json
import sys
from optparse import OptionParser
#
USE_REGEX = re.compile(r'([ \t]*USE )', re.I)
SUB_REGEX = re.compile(r'([ \t]*(PURE|ELEMENTAL|RECURSIVE)?[ \t]*(SUBROUTINE))', re.I)
END_SUB_REGEX = re.compile(r'([ \t]*(END)[ \t]*(SUBROUTINE))', re.I)
FUN_REGEX = re.compile(r'([ \t]*(PURE|ELEMENTAL|RECURSIVE)?[ \t]*(FUNCTION))', re.I)
END_FUN_REGEX = re.compile(r'([ \t]*(END)[ \t]*(FUNCTION))', re.I)
MOD_REGEX = re.compile(r'([ \t]*(MODULE))', re.I)
END_MOD_REGEX = re.compile(r'([ \t]*(END)[ \t]*(MODULE))', re.I)
PROG_REGEX = re.compile(r'([ \t]*(PROGRAM))', re.I)
END_PROG_REGEX = re.compile(r'([ \t]*(END)[ \t]*(PROGRAM))', re.I)
INT_REGEX = re.compile(r'([ \t]*(INTERFACE))', re.I)
END_INT_REGEX = re.compile(r'([ \t]*(END)[ \t]*(INTERFACE))', re.I)
TYPE_DEF_REGEX = re.compile(r'([ \t]*(TYPE)[ \t,])', re.I)
EXTENDS_REGEX = re.compile(r'EXTENDS[ ]*\([a-z0-9_]*\)', re.I)
END_TYPED_REGEX = re.compile(r'([ \t]*(END)[ \t]*(TYPE))', re.I)
INT_PRO_REGEX = re.compile(r'([ \t]*(MODULE[ \t]*PROCEDURE))', re.I)
NAT_VAR_DEF_REGEX = re.compile(r'([ \t]*(INTEGER|REAL|DOUBLE PRECISION|COMPLEX|CHARACTER|LOGICAL|PROCEDURE))', re.I)
UD_VAR_DEF_REGEX = re.compile(r'([ \t]*(CLASS\(|TYPE\(|PROCEDURE\())', re.I)
KEYWORD_REGEX = re.compile(r'(PUBLIC|PRIVATE|ALLOCATABLE|POINTER|DIMENSION|PURE)', re.I)
VIS_REGEX = re.compile(r'(PUBLIC|PRIVATE)', re.I)
WORD_REGEX = re.compile(r'[a-z][a-z0-9_]*', re.I)
LINK_REGEX = re.compile(r'([a-z][a-z0-9_]*[ \t]*)=>([ \t]*[a-z][a-z0-9_]*)', re.I)
SUB_PAREN_MATCH = re.compile(r'\([a-z0-9_, ]*\)', re.I)
KIND_SPEC_MATCH = re.compile(r'\([a-z0-9_, =]*\)', re.I)
COMMENT_LINE_MATCH = re.compile(r'([ \t]*!)')
CONT_REGEX = re.compile(r'([ \t]*&)')
#
class fortran_scope:
    def __init__(self, line_number, name, enc_scope=None, args=None):
        self.sline = line_number
        self.eline = None
        self.name = name.lower()
        self.children = []
        self.use = []
        self.parent = None
        self.vis = 0
        self.args = args
        if enc_scope is not None:
            self.FQSN = enc_scope.lower() + "::" + self.name
        else:
            self.FQSN = self.name
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
        return 'unknown'
    def get_desc(self):
        return 'unknown'
    def end(self, line_number):
        self.eline = line_number
    def write_scope(self):
        scope_dict = {'name': self.name, 'type': self.get_type(), 'desc': self.get_desc(), 'fbound': [self.sline, self.eline], 'children': []}#{}}
        if self.args is not None:
            scope_dict['args'] = self.args
        if len(self.children) > 0:
            for child in self.children:
                scope_dict['children'].append(child.name)
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
        self.name = name.lower()
        self.children = []
        self.use = []
        self.parent = None
        self.vis = 0
        self.args = args
        if enc_scope is not None:
            self.FQSN = enc_scope.lower() + "::" + self.name
        else:
            self.FQSN = self.name
    def get_type(self):
        return 'module'
    def get_desc(self):
        return 'MODULE'
#
class fortran_program(fortran_scope):
    def __init__(self, line_number, name, enc_scope=None, args=None):
        self.sline = line_number
        self.eline = None
        self.name = name.lower()
        self.children = []
        self.use = []
        self.parent = None
        self.vis = 0
        self.args = args
        if enc_scope is not None:
            self.FQSN = enc_scope.lower() + "::" + self.name
        else:
            self.FQSN = self.name
    def get_type(self):
        return 'module'
    def get_desc(self):
        return 'PROGRAM'
#
class fortran_subroutine(fortran_scope):
    def __init__(self, line_number, name, enc_scope=None, args=None):
        self.sline = line_number
        self.eline = None
        self.name = name.lower()
        self.children = []
        self.use = []
        self.parent = None
        self.vis = 0
        self.args = args
        if enc_scope is not None:
            self.FQSN = enc_scope.lower() + "::" + self.name
        else:
            self.FQSN = self.name
    def get_type(self):
        return 'method'
    def get_desc(self):
        return 'SUBROUTINE'
#
class fortran_function(fortran_scope):
    def __init__(self, line_number, name, enc_scope=None, args=None):
        self.sline = line_number
        self.eline = None
        self.name = name.lower()
        self.children = []
        self.use = []
        self.parent = None
        self.vis = 0
        self.args = args
        if enc_scope is not None:
            self.FQSN = enc_scope.lower() + "::" + self.name
        else:
            self.FQSN = self.name
    def get_type(self):
        return 'function'
    def get_desc(self):
        return 'FUNCTION'
#
class fortran_type(fortran_scope):
    def __init__(self, line_number, name, enc_scope=None, args=None):
        self.sline = line_number
        self.eline = None
        self.name = name.lower()
        self.children = []
        self.use = []
        self.parent = None
        self.vis = 0
        self.args = args
        if enc_scope is not None:
            self.FQSN = enc_scope.lower() + "::" + self.name
        else:
            self.FQSN = self.name
    def get_type(self):
        return 'class'
    def get_desc(self):
        return 'TYPE'
#
class fortran_int(fortran_scope):
    def __init__(self, line_number, name, enc_scope=None, args=None):
        self.sline = line_number
        self.eline = None
        self.name = name.lower()
        self.children = []
        self.use = []
        self.parent = None
        self.vis = 0
        self.args = args
        if enc_scope is not None:
            self.FQSN = enc_scope.lower() + "::" + self.name
        else:
            self.FQSN = self.name
    def add_child(self, child_fqn):
        self.children.append(child_fqn)
    def get_type(self):
        return 'interface'
    def get_desc(self):
        return 'INTERFACE'
    def write_scope(self):
        child_list = []
        for child in self.children:
            child_list.append(child)
        scope_dict = {'name': self.name, 'type': 'copy', 'children': child_list}
        if self.vis == -1:
            scope_dict['vis'] = '-1'
        elif self.vis == 1:
            scope_dict['vis'] = '1'
        return scope_dict
#
class fortran_obj:
    def __init__(self, line_number, name, var_desc, enc_scope=None, link_obj=None):
        self.sline = line_number
        self.name = name.lower()
        self.desc = var_desc
        self.children = []
        self.vis = 0
        if link_obj is not None:
            self.link_obj = link_obj.lower()
        else:
            self.link_obj = None
        if enc_scope is not None:
            self.FQSN = enc_scope.lower() + "::" + self.name
        else:
            self.FQSN = self.name
    def set_visibility(self, new_vis):
        self.vis = new_vis
    def get_type(self):
        return 'variable'
    def get_desc(self):
        return self.desc
    def write_scope(self):
        scope_dict = {'name': self.name, 'type': self.get_type(), 'desc': self.get_desc()}
        if self.vis == -1:
            scope_dict['vis'] = '-1'
        elif self.vis == 1:
            scope_dict['vis'] = '1'
        if self.link_obj is not None:
            scope_dict['link'] = self.link_obj
        return scope_dict
#
def parse_subroutine_def(test_str):
    name = None
    args = None
    paren_count = 0
    i=0
    n = len(test_str)
    found_name = False
    #
    word_match = WORD_REGEX.findall(test_str)
    for word in word_match:
        if word == '':
            continue
        key_match = KEYWORD_REGEX.match(word)
        if key_match is None:
            name = word
            break
    if name is not None:
        trailing_line = test_str.split(name)[1].strip()
        paren_match = SUB_PAREN_MATCH.match(trailing_line)
        if paren_match is not None:
            word_match = WORD_REGEX.findall(paren_match.group(0))
            if word_match is not None:
                args = ','.join(word_match)
    #
    return name, args
#
def parse_type_def(test_str):
    name = None
    parent = None
    # Get name
    test_split = test_str.split('::')
    if(len(test_split)>1):
        word_match = WORD_REGEX.findall(test_split[1])
        if len(word_match)>0:
            name = word_match[0]
    # Look for parent
    ext_match = EXTENDS_REGEX.findall(test_split[0])
    if len(ext_match)>0:
        i1 = ext_match[0].find('(')
        i2 = ext_match[0].find(')')
        if i1>=0 and i2>=0:
            parent = ext_match[0][i1+1:i2]
    #
    return name, parent
#
def get_first_nonkey(test_str):
    word_match = WORD_REGEX.findall(test_str)
    for word in word_match:
        if word == '':
            continue
        key_match = KEYWORD_REGEX.match(word)
        if key_match is None:
            return word
    return None
#
def get_all_vdefs(test_str):
    words = []
    paren_count = 0
    in_assign = False
    i=0
    n = len(test_str)
    while(True):
        if i >= n:
            break
        if test_str[i] == '!':
            break
        if paren_count == 0 and (not in_assign):
            str_match = WORD_REGEX.match(test_str[i:])
            if str_match is not None:
                if str_match.start(0) == 0:
                    words.append(str_match.group(0))
                    i+=str_match.end(0)
                    continue
            if test_str[i] == '=':
                in_assign = True
        #
        if test_str[i] == '(':
            paren_count += 1
        elif test_str[i] == ')':
            paren_count -= 1
        #
        if in_assign and paren_count == 0:
            if test_str[i] == ',':
                in_assign = False
        i+=1
    #
    return words
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
            for scope in self.scope_stack:
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
    def dump_json(self):
        if len(self.scope_stack) > 0:
            print json.dumps({'error': 'Scope stack not empty'}, indent=self.indent_level)
            return
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
        print json.dumps(js_output, indent=self.indent_level)

#
def read_visibility(def_str):
    vis_match = VIS_REGEX.findall(def_str)
    curr_vis = 0
    if len(vis_match) > 0:
        if vis_match[0].lower() == 'private':
            curr_vis = -1
        else:
            curr_vis = 1
    return curr_vis
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
parser.add_option("--file", dest="file", default=None,
                  help="Directories to parse")
(options, args) = parser.parse_args()
debug = options.debug
#
if options.std:
    filename = 'STDIN'
    f = sys.stdin
else:
    filename = options.file
    f = open(filename)
#
indent_level = None
if options.pretty:
    indent_level = 2
file_obj = fortran_file(indent_level)
line_number = 0
next_line_num = 1
at_eof = False
while(not at_eof):
    # Get next line
    line = f.readline()
    line_number = next_line_num
    next_line_num = line_number + 1
    if line == '':
        break # Reached end of file
    # Skip comment lines
    match = COMMENT_LINE_MATCH.match(line)
    if (match is not None):
        continue
    # Merge lines with continuations
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
        cont_match = CONT_REGEX.match(next_line)
        if cont_match is not None:
            next_line = next_line[cont_match.end(0):]
        next_line_num += 1
        line = split_line[0].rstrip() + next_line
        iAmper = line.find('&')
        iComm = line.find('!')
        if iComm < 0:
            iComm = iAmper + 1
    # Test for variable defs
    match = NAT_VAR_DEF_REGEX.match(line)
    if (match is not None):
        scope_word = match.group(0).strip()
        trailing_line = line[match.end(0):]
        fun_match = FUN_REGEX.match(trailing_line)
        if fun_match is not None: # Actually function def
            trailing_line = trailing_line[fun_match.end(0):]
            name, args = parse_subroutine_def(trailing_line)
            if name is not None:
                new_sub = fortran_function(line_number, name, file_obj.enc_scope_name, args)
                file_obj.add_scope(new_sub, END_FUN_REGEX)
                if(debug):
                    print 'Found function start, {0}:{1}, {2}'.format(filename, line_number, line[:-1])
                continue
        # Parse variable def
        kind_match = KIND_SPEC_MATCH.match(trailing_line)
        if kind_match is not None:
            scope_word += kind_match.group(0).strip()
        line_split = line.split('::')
        if len(line_split) == 1:
            continue
        if file_obj.current_scope is None:
            continue # Skip if no enclosing scope (something is wrong!)
        curr_vis = read_visibility(line_split[0])
        var_def_type = scope_word
        line_post_sep = line_split[1]
        # Look for link
        link_match = LINK_REGEX.match(line_post_sep.strip())
        if link_match is not None:
            var_key = link_match.group(1).strip()
            parent_key = link_match.group(2).strip()
            if parent_key.lower() != 'null':
                new_var = fortran_obj(line_number, var_key, scope_word.upper(), file_obj.enc_scope_name, parent_key)
                file_obj.add_variable(new_var)
                continue
        keys = get_all_vdefs(line_post_sep)
        if keys is not None:
            for key in keys:
                new_var = fortran_obj(line_number, key, scope_word.upper(), file_obj.enc_scope_name)
                new_var.set_visibility(curr_vis)
                file_obj.add_variable(new_var)
        if(debug):
            print 'Found native variable, {0}:{1}, {2}'.format(filename, line_number, line[:-1])
    # Test for user-defined and procedure variables
    match = UD_VAR_DEF_REGEX.match(line)
    if (match is not None):
        scope_word = match.group(0).strip()
        first_char = scope_word[0].lower()
        if first_char == 'p': # Procedure found
            end_ind = line[match.end(0):].find(')')
            scope_word = line[:end_ind+1+match.end(0)].strip()
            line_split = line.split('::')
            if len(line_split) == 1:
                continue
            if file_obj.current_scope is None:
                continue # Skip if no enclosing scope (something is wrong!)
            curr_vis = read_visibility(line_split[0])
            line_post_sep = line_split[1]
            keys = get_all_vdefs(line_post_sep)
            if keys is not None:
                for key in keys:
                    new_var = fortran_obj(line_number, key, scope_word.upper(), file_obj.enc_scope_name)
                    new_var.set_visibility(curr_vis)
                    file_obj.add_variable(new_var)
            if(debug):
                print 'Found procedure, {0}:{1}, {2}'.format(filename, line_number, line[:-1])
        else: # UD-Type found
            end_ind = line[match.end(0):].find(')')
            scope_word = line[:end_ind+1+match.end(0)].strip()
            line_split = line.split('::')
            if len(line_split) == 1:
                continue
            if file_obj.current_scope is None:
                continue # Skip if no enclosing scope (something is wrong!)
            curr_vis = read_visibility(line_split[0])
            line_post_sep = line_split[1]
            keys = get_all_vdefs(line_post_sep)
            if keys is not None:
                for key in keys:
                    new_var = fortran_obj(line_number, key, scope_word.upper(), file_obj.enc_scope_name)
                    new_var.set_visibility(curr_vis)
                    file_obj.add_variable(new_var)
            if(debug):
                print 'Found UD-type variable, {0}:{1}, {2}'.format(filename, line_number, line[:-1])
        continue
    # Test for scope end
    if file_obj.END_REGEX is not None:
        match = file_obj.END_REGEX.match(line)
        if (match is not None):
            file_obj.end_scope(line_number)
            if(debug):
                print 'Found scope end, {0}:{1}, {2}'.format(filename, line_number, line[:-1])
            continue
    # Test for start of subroutine
    match = SUB_REGEX.match(line)
    if (match is not None):
        trailing_line = line[match.end(0):]
        name, args = parse_subroutine_def(trailing_line)
        if name is not None:
            new_sub = fortran_subroutine(line_number, name, file_obj.enc_scope_name, args)
            file_obj.add_scope(new_sub, END_SUB_REGEX)
        if(debug):
            print 'Found subroutine start, {0}:{1}, {2}'.format(filename, line_number, line[:-1])
        continue
    # Test for start of function
    match = FUN_REGEX.match(line)
    if (match is not None):
        trailing_line = line[match.end(0):]
        name, args = parse_subroutine_def(trailing_line)
        if name is not None:
            new_sub = fortran_function(line_number, name, file_obj.enc_scope_name, args)
            file_obj.add_scope(new_sub, END_FUN_REGEX)
        if(debug):
            print 'Found function start, {0}:{1}, {2}'.format(filename, line_number, line[:-1])
        continue
    # Test for interface procedures
    match = INT_PRO_REGEX.match(line)
    if (match is not None):
        trailing_line = line[match.end(0):]
        first_key = get_first_nonkey(trailing_line)
        if first_key is not None:
            if file_obj.current_scope is None:
                continue
            if not isinstance(file_obj.current_scope,fortran_int):
                continue
            keys = get_all_vdefs(trailing_line.lower().replace('procedure',''))
            if keys is not None:
                for key in keys:
                    file_obj.add_int_member(key)
            if(debug):
                print 'Found procedure link, {0}:{1}, {2}'.format(filename, line_number, line[:-1])
            continue
    # Test for start of Interface
    match = INT_REGEX.match(line)
    if (match is not None):
        trailing_line = line[match.end(0):]
        first_key = get_first_nonkey(trailing_line)
        if first_key is not None: # Found named interface
            if first_key.lower() == 'operator' or first_key.lower() == 'assignment':
                continue
            new_int = fortran_int(line_number, first_key, file_obj.enc_scope_name)
            file_obj.add_scope(new_int, END_INT_REGEX, True)
        if(debug):
            print 'Found interface start, {0}:{1}, {2}'.format(filename, line_number, line[:-1])
        continue
    # Test for Type defs
    match = TYPE_DEF_REGEX.match(line)
    if (match is not None):
        trailing_line = line[match.end(0):]
        curr_vis = read_visibility(trailing_line)
        name, parent = parse_type_def(trailing_line)
        if name is not None:
            new_type = fortran_type(line_number, name, file_obj.enc_scope_name)
            new_type.set_visibility(curr_vis)
            if parent is not None:
                new_type.set_parent(parent)
            file_obj.add_scope(new_type, END_TYPED_REGEX, True)
        if(debug):
            print 'Found type definition, {0}:{1}, {2}'.format(filename, line_number, line[:-1])
        continue
    # Test for start of Module
    match = MOD_REGEX.match(line)
    if (match is not None):
        trailing_line = line[match.end(0):]
        first_key = get_first_nonkey(trailing_line)
        if first_key is not None:
            new_mod = fortran_module(line_number, first_key, file_obj.enc_scope_name)
            file_obj.add_scope(new_mod, END_MOD_REGEX)
        if(debug):
            print 'Found module start, {0}:{1}, {2}'.format(filename, line_number, line[:-1])
        continue
    # Test for start of Program
    match = PROG_REGEX.match(line)
    if (match is not None):
        trailing_line = line[match.end(0):]
        first_key = get_first_nonkey(trailing_line)
        if first_key is not None:
            new_mod = fortran_program(line_number, first_key, file_obj.enc_scope_name)
            file_obj.add_scope(new_mod, END_PROG_REGEX)
        if(debug):
            print 'Found program start, {0}:{1}, {2}'.format(filename, line_number, line[:-1])
        continue
    # Test for USE statements
    match = USE_REGEX.match(line)
    if (match is not None):
        trailing_line = line[match.end(0):]
        mod_words = get_all_vdefs(trailing_line)
        file_obj.add_use(mod_words)
        if(debug):
            print 'Found USE definition, {0}:{1}, {2}'.format(filename, line_number, line[:-1])
        continue
    # Look for visiblity statement
    match = VIS_REGEX.match(line)
    if (match is not None):
        match_lower = match.group(0).lower()
        trailing_line = line[match.end(0):]
        mod_words = get_all_vdefs(trailing_line)
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
            print 'Found visiblity statement, {0}:{1}, {2}'.format(filename, line_number, line[:-1])
        continue
f.close()
#
file_obj.dump_json()
