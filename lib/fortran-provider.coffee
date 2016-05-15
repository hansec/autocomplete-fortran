{BufferedProcess, File} = require 'atom'
fs = require('fs')
path = require('path')

module.exports =
class FortranProvider
  selector: '.source.fortran'
  disableForSelector: '.source.fortran .comment'
  inclusionPriority: 1
  suggestionPriority: 2

  pythonPath: ''
  parserPath: ''
  firstRun: true

  fileObjInd: { }
  globalObjInd: []
  projectObjList: { }
  exclPaths: []
  modDirs: []
  modFiles: []
  descList: []

  constructor: () ->
    @pythonPath = atom.config.get('autocomplete-fortran.pythonPath')
    @parserPath = path.join(__dirname, "..", "python", "parse_fortran.py")

  rebuildIndex: () ->
    # Reset index
    @modDirs = []
    @modFiles = []
    @fileObjInd = { }
    @globalObjInd = []
    @projectObjList = { }
    @descList = []
    # Build index
    @findModFiles()
    for filePath in @modFiles
      @fileUpdate(filePath)

  findModFiles: ()->
    F90Regex = /[a-z0-9_]*\.F90/i
    projectDirs = atom.project.getPaths()
    @modDirs = projectDirs
    @exclPaths = []
    for projDir in projectDirs
      settingPath = path.join(projDir, '.ac_fortran')
      try
        fs.accessSync(settingPath, fs.R_OK)
        fs.openSync(settingPath, 'r+')
        result = fs.readFileSync(settingPath)
        configOptions = JSON.parse(result)
        if 'excl_paths' of configOptions
          for exclPath in configOptions['excl_paths']
            @exclPaths.push(path.join(projDir, exclPath))
        if 'mod_dirs' of configOptions
          @modDirs = []
          for modDir in configOptions['mod_dirs']
            @modDirs.push(path.join(projDir, modDir))
    for modDir in @modDirs
      files = fs.readdirSync(modDir)
      for file in files
        if file.match(F90Regex)
          filePath = path.join(modDir, file)
          if @exclPaths.indexOf(filePath) == -1
            @modFiles.push(filePath)

  fileUpdate: (filePath)->
    command = @pythonPath
    args = [@parserPath,"--file=#{filePath}"]
    #
    new Promise (resolve) =>
      allOutput = []
      stdout = (output) => allOutput.push(output)
      stderr = (output) => console.log output
      exit = (code) => resolve(@handleCompletionResult(allOutput.join('\n'), code, filePath))
      bufferedProcess = new BufferedProcess({command, args, stdout, stderr, exit})

  localUpdate: (editor, row)->
    command = @pythonPath
    args = [@parserPath,"-s"]
    #
    new Promise (resolve) =>
      allOutput = []
      stdout = (output) => allOutput.push(output)
      stderr = (output) => console.log output
      exit = (code) => resolve(@handleCompletionResult(allOutput.join('\n'), code, editor.getPath()))
      bufferedProcess = new BufferedProcess({command, args, stdout, stderr, exit})
      bufferedProcess.process.stdin.setEncoding = 'utf-8';
      bufferedProcess.process.stdin.write(editor.getText())
      bufferedProcess.process.stdin.end()

  handleCompletionResult: (result,returnCode,filePath) ->
    if returnCode is not 0
      return
    try
      fileAST = JSON.parse(result)
    catch
      console.log 'Error parsing file:', filePath
      atom.notifications?.addError("Error parsing file '#{filePath}'", {
        detail: 'Script failed',
        dismissable: true
      })
      return
    #
    if 'error' of fileAST
      console.log 'Error parsing file:', filePath
      atom.notifications?.addError("Error parsing file '#{filePath}'", {
        detail: fileAST['error'],
        dismissable: true
      })
      return
    #
    for key of fileAST['objs']
      @projectObjList[key] = fileAST['objs'][key]
      if 'desc' of @projectObjList[key]
        descIndex = @descList.indexOf(@projectObjList[key]['desc'])
        if descIndex == -1
          @descList.push(@projectObjList[key]['desc'])
          @projectObjList[key]['desc'] = @descList.length-1
        else
          @projectObjList[key]['desc'] = descIndex
    @globalObjInd = []
    for key of @projectObjList
      if not key.match(/::/)
        @globalObjInd.push(key)
    @fileObjInd[filePath] = fileAST['scopes']
    #console.log 'Updated suggestions'

  getSuggestions: ({editor, bufferPosition, prefix}) ->
    unless @exclPaths.indexOf(editor.getPath()) == -1
      return []
    # Build index on first run
    if @firstRun
      @rebuildIndex()
      @firstRun = false
    # Get suggestions
    @localUpdate(editor, bufferPosition.row).then () =>
        @filterSuggestions(prefix, editor, bufferPosition)

  filterSuggestions: (prefix, editor, bufferPosition) ->
    completions = []
    if prefix
      prefixLower = prefix.toLowerCase()
      lineScopes = @getLineScopes(editor, bufferPosition)
      cursorScope = @getClassScope(editor, bufferPosition, lineScopes)
      if cursorScope?
        return @addChildren(cursorScope, completions, prefixLower, [])
      lineContext = @getLineContext(editor, bufferPosition)
      for key in @globalObjInd when (@projectObjList[key]['name'].startsWith(prefixLower))
        if @projectObjList[key]['type'] == 'module' and lineContext != 1
          continue
        completions.push(@buildCompletion(@projectObjList[key]))
      #
      for lineScope in lineScopes
        completions = @addChildren(lineScope, completions, prefixLower, [])
        # Process USE STMT
        if 'use' of @projectObjList[lineScope]
          for use_mod in @projectObjList[lineScope]['use']
            if use_mod[0] of @projectObjList
              if lineContext == 1
                completions = @addPublicChildren(use_mod[0], completions, prefixLower, [])
              else
                completions = @addPublicChildren(use_mod[0], completions, prefixLower, use_mod[1])
    else
      lineScopes = @getLineScopes(editor, bufferPosition)
      cursorScope = @getClassScope(editor, bufferPosition, lineScopes)
      if cursorScope?
        return @addChildren(cursorScope, completions, null, [])
    return completions

  getLineContext: (editor, bufferPosition) ->
    useRegex = /^[ \t]*use/i
    line = editor.getTextInRange([[bufferPosition.row, 0], bufferPosition])
    if line.match(useRegex)?
      return 1 # In use declaration
    return 0 # Unknown enable everything!!!!

  getLineScopes: (editor, bufferPosition) ->
    filePath = editor.getPath()
    scopes = []
    for key in @fileObjInd[filePath] # Look in currently active file for enclosing scopes
      if key of @projectObjList
        if bufferPosition.row+1 < @projectObjList[key]['fbound'][0]
          continue
        if bufferPosition.row+1 > @projectObjList[key]['fbound'][1]
          continue
        scopes.push(key)
    return scopes

  findInScope: (scope, name) ->
    FQN = scope + '::' + name
    if FQN of @projectObjList
      return scope
    # Check inherited
    if 'in_children' of @projectObjList[scope]
      for childKey in @projectObjList[scope]['in_children']
        childScopes = childKey.split('::')
        childName = childScopes.pop()
        if childName == name
          return childScopes.join('::')
    # Search in use
    result = null
    if 'use' of @projectObjList[scope]
      for use_mod in @projectObjList[scope]['use']
        if use_mod[0] of @projectObjList
          if use_mod[1].length > 0
            if use_mod[1].indexOf(name) == -1
              continue
          result = @findInScope(use_mod[0], name)
          if result?
            return result
    # Search parent
    if not result?
      endOfScope = scope.lastIndexOf('::')
      if endOfScope >=0
        newScope = scope.substring(0,endOfScope)
        result = @findInScope(newScope, name)
    return result

  getVarType: (varKey) ->
    varDesc = @descList[@projectObjList[varKey]['desc']]
    typeDef = varDesc.toLowerCase()
    i1 = typeDef.indexOf('(')
    i2 = typeDef.indexOf(')')
    return typeDef.substring(i1+1,i2)

  getClassScope: (editor, bufferPosition, currScopes) ->
    typeDerefCheck = /%/i
    objBreakReg = /[\(,=]/ig
    parenRepReg = /\(([^\)]+)\)/ig
    line = editor.getTextInRange([[bufferPosition.row, 0], bufferPosition])
    searchScope = null
    if line.match(typeDerefCheck)?
      lineNoParen = line.replace(parenRepReg,'')
      lineCommBreak = lineNoParen.replace(objBreakReg, ' ')
      lastSpace = lineCommBreak.lastIndexOf(' ')
      if lastSpace >=0
        lineNoParen = lineCommBreak.substring(lastSpace+1)
      splitLine = lineNoParen.split('%')
      prefixVar = splitLine.pop()
      for varName in splitLine
        if searchScope?
          @resolveIherited(searchScope)
          containingScope = @findInScope(searchScope, varName)
          if containingScope?
            varKey = containingScope + "::" + varName
            if @projectObjList[varKey]['type'].startsWith('var')
              varDefName = @getVarType(varKey)
              containingScope = @findInScope(containingScope, varDefName)
              searchScope = containingScope + '::' + varDefName
          else
            return null
        else
          for currScope in currScopes
            @resolveIherited(currScope)
            containingScope = @findInScope(currScope, varName)
            if containingScope?
              varKey = containingScope + "::" + varName
              if @projectObjList[varKey]['type'].startsWith('var')
                varDefName = @getVarType(varKey)
                containingScope = @findInScope(containingScope, varDefName)
                searchScope = containingScope + '::' + varDefName
              break
    return searchScope # Unknown enable everything!!!!

  addChildren: (scope, completions, prefix, only_list) ->
    unless scope of @projectObjList
      return completions
    unless 'children' of @projectObjList[scope]
      return
    children = @projectObjList[scope]['children']
    for child in children
      if prefix?
        unless child.startsWith(prefix)
          continue
      if only_list.length > 0
        if only_list.indexOf(child) == -1
          continue
      childKey = scope+'::'+child
      if childKey of @projectObjList
        if @projectObjList[childKey]['type'] == 'copy'
          @resolveInterface(childKey, scope)
          repName = @projectObjList[childKey]['name']
          for copyKey in @projectObjList[childKey]['res_children']
            completions.push(@buildCompletion(@projectObjList[copyKey], repName))
        else
          if 'link' of @projectObjList[childKey]
            @resolveLink(childKey, scope)
            repName = @projectObjList[childKey]['name']
            copyKey = @projectObjList[childKey]['res_link']
            completions.push(@buildCompletion(@projectObjList[copyKey], repName))
          else
            completions.push(@buildCompletion(@projectObjList[childKey]))
    # Add inherited
    @resolveIherited(scope)
    if 'in_children' of @projectObjList[scope]
      for childKey in @projectObjList[scope]['in_children']
        completions.push(@buildCompletion(@projectObjList[childKey]))
    # Process USE STMT (only if no only_list)
    if ('use' of @projectObjList[scope]) and (only_list.length == 0)
      for use_mod in @projectObjList[scope]['use']
        if use_mod[0] of @projectObjList
          completions = @addPublicChildren(use_mod[0], completions, prefix, use_mod[1])
    return completions

  addPublicChildren: (scope, completions, prefix, only_list) ->
    unless scope of @projectObjList
      return completions
    unless 'children' of @projectObjList[scope]
      return
    children = @projectObjList[scope]['children']
    curr_vis = 1
    if 'vis' of @projectObjList[scope]
      curr_vis = parseInt(@projectObjList[scope]['vis'])
    for child in children
      if prefix?
        unless child.startsWith(prefix)
          continue
      if only_list.length > 0
        if only_list.indexOf(child) == -1
          continue
      childKey = scope+'::'+child
      if childKey of @projectObjList
        if 'vis' of @projectObjList[childKey]
          if parseInt(@projectObjList[childKey]['vis']) + curr_vis < 0
            continue
        else
          if curr_vis < 0
            continue
        if @projectObjList[childKey]['type'] == 'copy'
          @resolveInterface(childKey, scope)
          repName = @projectObjList[childKey]['name']
          for copyKey in @projectObjList[childKey]['res_children']
            completions.push(@buildCompletion(@projectObjList[copyKey], repName))
        else
          if 'link' of @projectObjList[childKey]
            @resolveLink(childKey, scope)
            repName = @projectObjList[childKey]['name']
            copyKey = @projectObjList[childKey]['res_link']
            completions.push(@buildCompletion(@projectObjList[copyKey], repName))
          else
            completions.push(@buildCompletion(@projectObjList[childKey]))
    # Add inherited
    @resolveIherited(scope)
    if 'in_children' of @projectObjList[scope]
      for childKey in @projectObjList[scope]['in_children']
        completions.push(@buildCompletion(@projectObjList[childKey]))
    # Process USE STMT (only if no only_list)
    if ('use' of @projectObjList[scope]) and (only_list.length == 0)
      for use_mod in @projectObjList[scope]['use']
        if use_mod[0] of @projectObjList
          completions = @addPublicChildren(use_mod[0], completions, prefix, use_mod[1])
    return completions

  resolveInterface: (intObjKey, scope) ->
    if 'res_children' of @projectObjList[intObjKey]
      return
    resolvedChildren = []
    children = @projectObjList[intObjKey]['children']
    for copyKey in children
      resolvedScope = @findInScope(scope, copyKey)
      if resolvedScope?
        resolvedChildren.push(resolvedScope+"::"+copyKey)
    @projectObjList[intObjKey]['res_children'] = resolvedChildren

  resolveLink: (objKey, scope) ->
    unless 'link' of @projectObjList[objKey]
      return
    if 'res_link' of @projectObjList[objKey]
      return
    linkKey = @projectObjList[objKey]['link']
    resolvedScope = @findInScope(scope, linkKey)
    if resolvedScope?
      @projectObjList[objKey]['res_link'] = resolvedScope+"::"+linkKey

  resolveIherited: (scope) ->
    classObj = @projectObjList[scope]
    if 'in_children' of classObj
      return
    unless 'parent' of classObj
      return
    unless 'res_parent' of classObj
      parentName = classObj['parent']
      resolvedScope = @findInScope(scope, parentName)
      if resolvedScope?
        @projectObjList[scope]['res_parent'] = resolvedScope+"::"+parentName
      else
        return
    # Load from parent class
    parentKey = @projectObjList[scope]['res_parent']
    if parentKey of @projectObjList
      @resolveIherited(parentKey)
      #
      @projectObjList[scope]['in_children'] = []
      if 'children' of @projectObjList[scope]
        classChildren = @projectObjList[scope]['children']
      else
        classChildren = []
      if 'children' of @projectObjList[parentKey]
        for childKey in @projectObjList[parentKey]['children']
          if classChildren.indexOf(childKey) == -1
            @projectObjList[scope]['in_children'].push(parentKey+'::'+childKey)
      if 'in_children' of @projectObjList[parentKey]
        for childKey in @projectObjList[parentKey]['in_children']
          childName = childKey.split('::').pop()
          if classChildren.indexOf(childName) == -1
            @projectObjList[scope]['in_children'].push(childKey)
    return

  buildCompletion: (suggestion, repName=null) ->
    name = suggestion['name']
    if repName?
      name = repName
    if 'args' of suggestion
      type: suggestion['type']
      snippet: name + "(" + suggestion['args'] + ")"
      leftLabel: @descList[suggestion['desc']]
    else
      type: suggestion['type']
      text: name
      leftLabel: @descList[suggestion['desc']]
    #rightLabel: 'My Provider'
