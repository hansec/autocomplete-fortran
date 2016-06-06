{BufferedProcess, CompositeDisposable, File} = require 'atom'
fs = require('fs')
path = require('path')

module.exports =
class FortranProvider
  selector: '.source.fortran'
  disableForSelector: '.source.fortran .comment, .source.fortran .string.quoted'
  inclusionPriority: 1
  suggestionPriority: 2

  workspaceWatcher: undefined
  saveWatchers: undefined

  pythonPath: ''
  parserPath: ''
  minPrefix: 2
  firstRun: true
  indexReady: false
  lastFile: ''
  lastRow: -1

  fileObjInd: { }
  globalObjInd: []
  projectObjList: { }
  exclPaths: []
  modDirs: []
  modFiles: []
  fileIndexed: []
  descList: []

  constructor: () ->
    @pythonPath = atom.config.get('autocomplete-fortran.pythonPath')
    @parserPath = path.join(__dirname, "..", "python", "parse_fortran.py")
    @minPrefix = atom.config.get('autocomplete-fortran.minPrefix')
    @saveWatchers = new CompositeDisposable
    @workspaceWatcher = atom.workspace.observeTextEditors((editor) => @setupEditors(editor))

  destructor: () ->
    if @workspaceWatcher?
      @workspaceWatcher.dispose()
    if @saveWatchers?
      @saveWatchers.dispose()

  setupEditors: (editor) ->
    @saveWatchers.add editor.onDidSave((event) => @fileUpdateSave(event))

  fileUpdateSave: (event) ->
    fileRef = @modFiles.indexOf(event.path)
    if fileRef > -1
      @fileUpdate(event.path)

  rebuildIndex: () ->
    # Reset index
    @indexReady = false
    @lastFile = ''
    @lastRow = -1
    @modDirs = []
    @modFiles = []
    @fileIndexed = []
    @fileObjInd = { }
    @globalObjInd = []
    @projectObjList = { }
    @descList = []
    # Build index
    @findModFiles()
    for filePath in @modFiles
      @fileUpdate(filePath)

  checkIndex: () ->
    if @indexReady
      return true
    for isIndexed in @fileIndexed
      unless isIndexed
        return false
    @indexReady = true
    return true

  notifyBuildPending: (operation) ->
    atom.notifications?.addWarning("Could not complete operation: #{operation}", {
      detail: 'Indexing pending',
      dismissable: true
    })

  findModFiles: ()->
    F90Regex = /[a-z0-9_]*\.F90$/i
    F77Regex = /[a-z0-9_]*\.F$/i
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
        if file.match(F90Regex) or file.match(F77Regex)
          filePath = path.join(modDir, file)
          if @exclPaths.indexOf(filePath) == -1
            @modFiles.push(filePath)
            @fileIndexed.push(false)

  fileUpdate: (filePath)->
    F77Regex = /[a-z0-9_]*\.F$/i
    command = @pythonPath
    args = [@parserPath,"--file=#{filePath}"]
    if filePath.match(F77Regex)
      args.push("--fixed")
    #
    new Promise (resolve) =>
      allOutput = []
      stdout = (output) => allOutput.push(output)
      stderr = (output) => console.log output
      exit = (code) => resolve(@handleCompletionResult(allOutput.join('\n'), code, filePath))
      bufferedProcess = new BufferedProcess({command, args, stdout, stderr, exit})

  localUpdate: (editor, row)->
    F77Regex = /[a-z0-9_]*\.F$/i
    filePath = editor.getPath()
    command = @pythonPath
    args = [@parserPath,"-s"]
    if filePath.match(F77Regex)
      args.push("--fixed")
    #
    new Promise (resolve) =>
      allOutput = []
      stdout = (output) => allOutput.push(output)
      stderr = (output) => console.log output
      exit = (code) => resolve(@handleCompletionResult(allOutput.join('\n'), code, filePath))
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
    fileRef = @modFiles.indexOf(filePath)
    if fileRef == -1
      @modFiles.push(filePath)
      fileRef = @modFiles.indexOf(filePath)
    for key of fileAST['objs']
      if key of @projectObjList
        @resetInherit(@projectObjList[key])
      @projectObjList[key] = fileAST['objs'][key]
      @projectObjList[key]['file'] = fileRef
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
    @fileIndexed[fileRef] = true
    #console.log 'Updated suggestions'

  getSuggestions: ({editor, bufferPosition, prefix, activatedManually}) ->
    unless @exclPaths.indexOf(editor.getPath()) == -1
      return []
    # Build index on first run
    if @firstRun
      @rebuildIndex()
      @firstRun = false
    return new Promise (resolve) =>
      # Check if update requred
      parseBuffer = false
      if @lastFile != editor.getPath()
        parseBuffer = true
        @lastFile = editor.getPath()
      if @lastRow != bufferPosition.row
        parseBuffer = true
        @lastRow = bufferPosition.row
      # Get suggestions
      if parseBuffer
        @localUpdate(editor, bufferPosition.row).then () =>
          resolve(@filterSuggestions(prefix, editor, bufferPosition, activatedManually))
      else
        resolve(@filterSuggestions(prefix, editor, bufferPosition, activatedManually))

  filterSuggestions: (prefix, editor, bufferPosition, activatedManually) ->
    completions = []
    if prefix
      prefixLower = prefix.toLowerCase()
      lineContext = @getLineContext(editor, bufferPosition)
      if lineContext == 2
        return completions
      if lineContext == 1
        return @getUseSuggestion(editor, bufferPosition, prefixLower)
      lineScopes = @getLineScopes(editor, bufferPosition)
      cursorScope = @getClassScope(editor, bufferPosition, lineScopes)
      if cursorScope?
        return @addChildren(cursorScope, completions, prefixLower, [])
      if prefix.length < @minPrefix and not activatedManually
        return completions
      for key in @globalObjInd when (@projectObjList[key]['name'].startsWith(prefixLower))
        if @projectObjList[key]['type'] == 'module'
          continue
        completions.push(@buildCompletion(@projectObjList[key]))
      #
      usedMod = { }
      for lineScope in lineScopes
        completions = @addChildren(lineScope, completions, prefixLower, [])
        usedMod = @getUseSearches(lineScope, usedMod, [])
      for useMod of usedMod
        completions = @addPublicChildren(useMod, completions, prefixLower, usedMod[useMod])
    else
      line = editor.getTextInRange([[bufferPosition.row, 0], bufferPosition])
      unless line.endsWith('%')
        return completions
      lineScopes = @getLineScopes(editor, bufferPosition)
      cursorScope = @getClassScope(editor, bufferPosition, lineScopes)
      if cursorScope?
        return @addChildren(cursorScope, completions, null, [])
    return completions

  goToDef: (word, editor, bufferPosition) ->
    # Build index on first run
    if @firstRun
      @rebuildIndex()
      @firstRun = false
    @localUpdate(editor, bufferPosition.row)
    unless @checkIndex()
      @notifyBuildPending('Go To Definition')
      return
    wordLower = word.toLowerCase()
    lineScopes = @getLineScopes(editor, bufferPosition)
    # Look up class tree
    cursorScope = @getClassScope(editor, bufferPosition, lineScopes)
    if cursorScope?
      @resolveIherited(cursorScope)
      containingScope = @findInScope(cursorScope, wordLower)
      if containingScope?
        FQN = containingScope+"::"+wordLower
        return @getDefLoc(@projectObjList[FQN])
    # Look in global context
    if @globalObjInd.indexOf(wordLower) != -1
      return @getDefLoc(@projectObjList[wordLower])
    # Look in local scopes
    for lineScope in lineScopes
      containingScope = @findInScope(lineScope, wordLower)
      if containingScope?
        FQN = containingScope+"::"+wordLower
        return @getDefLoc(@projectObjList[FQN])
    return null

  getDefLoc: (varObj) ->
    fileRef = varObj['file']
    lineRef = null
    if 'fdef' of varObj
      lineRef = varObj['fdef']
    if 'fbound' of varObj
      lineRef = varObj['fbound'][0]
    if lineRef?
      return @modFiles[fileRef]+":"+lineRef.toString()
    return null

  getUseSuggestion: (editor, bufferPosition, prefixLower) ->
    useRegex = /^[ \t]*use[ \t]+/i
    wordRegex = /[a-z0-9_]+/gi
    suggestions = []
    line = editor.getTextInRange([[bufferPosition.row, 0], bufferPosition])
    if line.match(useRegex)?
      unless prefixLower.match(wordRegex)?
        prefixLower = ""
      matches = line.match(wordRegex)
      if matches.length == 2
        if prefixLower?
          for key in @globalObjInd when (@projectObjList[key]['name'].startsWith(prefixLower))
            if @projectObjList[key]['type'] != 'module'
              continue
            suggestions.push(@buildCompletion(@projectObjList[key]))
        else
          for key in @globalObjInd
            suggestions.push(@buildCompletion(@projectObjList[key]))
        return suggestions
      else if matches.length > 2
        modName = matches[1]
        suggestions = @addPublicChildren(modName, suggestions, prefixLower, [])
        for suggestion in suggestions
          if 'snippet' of suggestion
            suggestion.snippet = suggestion.snippet.split('(')[0]
        return suggestions
    return suggestions # Unknown enable everything!!!!

  getLineContext: (editor, bufferPosition) ->
    useRegex = /^[ \t]*USE[ \t]/i
    subDefRegex = /^[ \t]*(PURE|ELEMENTAL|RECURSIVE)*[ \t]*(MODULE|PROGRAM|SUBROUTINE|FUNCTION)[ \t]/i
    line = editor.getTextInRange([[bufferPosition.row, 0], bufferPosition])
    if line.match(useRegex)?
      return 1
    if line.match(useRegex)?
      return 2
    return 0

  getLineScopes: (editor, bufferPosition) ->
    filePath = editor.getPath()
    scopes = []
    unless @fileObjInd[filePath]?
      return []
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
    if 'in_mem' of @projectObjList[scope]
      for childKey in @projectObjList[scope]['in_mem']
        childScopes = childKey.split('::')
        childName = childScopes.pop()
        if childName == name
          return childScopes.join('::')
    # Search in use
    result = null
    usedMod = @getUseSearches(scope, { }, [])
    for useMod of usedMod
      if usedMod[useMod].length > 0
        if usedMod[useMod].indexOf(name) == -1
          continue
      result = @findInScope(useMod, name)
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
    objBreakReg = /[\/\-(.,+*<>=$:]/ig
    parenRepReg = /\((.+)\)/ig
    line = editor.getTextInRange([[bufferPosition.row, 0], bufferPosition])
    #
    unless line.match(typeDerefCheck)?
      return null
    parenCount = 0
    lineCopy = line
    for i in [0..lineCopy.length-1]
      currChar = lineCopy[lineCopy.length-i-1]
      if parenCount == 0 and currChar.match(objBreakReg)
        line = lineCopy.substring(lineCopy.length-i)
        break
      if currChar == '('
        parenCount -= 1
      if currChar == ')'
        parenCount += 1
    searchScope = null
    if line.match(typeDerefCheck)?
      lineNoParen1 = line.replace(parenRepReg,'$')
      lineNoParen = lineNoParen1.replace(/\$%/i,'%')
      lineCommBreak = lineNoParen.replace(objBreakReg, ' ')
      lastSpace = lineCommBreak.lastIndexOf(' ')
      if lastSpace >=0
        lineNoParen = lineCommBreak.substring(lastSpace+1)
      splitLine = lineNoParen.split('%')
      prefixVar = splitLine.pop()
      for varName in splitLine
        varNameLower = varName.toLowerCase()
        if searchScope?
          @resolveIherited(searchScope)
          containingScope = @findInScope(searchScope, varNameLower)
          if containingScope?
            varKey = containingScope + "::" + varNameLower
            if @projectObjList[varKey]['type'].startsWith('var')
              varDefName = @getVarType(varKey)
              containingScope = @findInScope(containingScope, varDefName)
              searchScope = containingScope + '::' + varDefName
          else
            return null
        else
          for currScope in currScopes
            @resolveIherited(currScope)
            containingScope = @findInScope(currScope, varNameLower)
            if containingScope?
              varKey = containingScope + "::" + varNameLower
              if @projectObjList[varKey]['type'].startsWith('var')
                varDefName = @getVarType(varKey)
                containingScope = @findInScope(containingScope, varDefName)
                searchScope = containingScope + '::' + varDefName
              break
    return searchScope # Unknown enable everything!!!!

  addChildren: (scope, completions, prefix, onlyList) ->
    unless scope of @projectObjList
      return completions
    unless 'mem' of @projectObjList[scope]
      return
    children = @projectObjList[scope]['mem']
    for child in children
      if prefix?
        unless child.startsWith(prefix)
          continue
      if onlyList.length > 0
        if onlyList.indexOf(child) == -1
          continue
      childKey = scope+'::'+child
      if childKey of @projectObjList
        if @projectObjList[childKey]['type'] == 'copy'
          @resolveInterface(childKey, scope)
          repName = @projectObjList[childKey]['name']
          for copyKey in @projectObjList[childKey]['res_mem']
            completions.push(@buildCompletion(@projectObjList[copyKey], repName))
        else
          if 'link' of @projectObjList[childKey]
            @resolveLink(childKey, scope)
            repName = @projectObjList[childKey]['name']
            copyKey = @projectObjList[childKey]['res_link']
            doPass = false
            if @projectObjList[scope]['type'] == 'class'
              doPass = @testPass(@projectObjList[childKey])
            completions.push(@buildCompletion(@projectObjList[copyKey], repName, doPass))
          else
            completions.push(@buildCompletion(@projectObjList[childKey]))
    # Add inherited
    @resolveIherited(scope)
    if 'in_mem' of @projectObjList[scope]
      for childKey in @projectObjList[scope]['in_mem']
        completions.push(@buildCompletion(@projectObjList[childKey]))
    return completions

  getUseSearches: (scope, modDict, onlyList) ->
    # Process USE STMT (only if no onlyList)
    if 'use' of @projectObjList[scope]
      for useMod in @projectObjList[scope]['use']
        if useMod[0] of @projectObjList
          mergedOnly = @getOnlyOverlap(onlyList, useMod[1])
          unless mergedOnly?
            continue
          if useMod[0] of modDict
            if modDict[useMod[0]].length > 0
              if mergedOnly.length == 0
                modDict[useMod[0]] = []
              else
                for only in mergedOnly
                  if modDict[useMod[0]].indexOf(only) == -1
                    modDict[useMod[0]].push(only)
          else
            modDict[useMod[0]] = mergedOnly
          modDict = @getUseSearches(useMod[0], modDict, mergedOnly)
    return modDict

  getOnlyOverlap: (currList, newList) ->
    if currList.length == 0
      return newList
    if newList.length == 0
      return currList
    mergeList = []
    hasOverlap = false
    for elem in newList
      unless currList.indexOf(elem) == -1
        mergeList.push(elem)
        hasOverlap = true
    if hasOverlap
      return mergeList
    else
      return null

  addPublicChildren: (scope, completions, prefix, onlyList) ->
    unless scope of @projectObjList
      return completions
    unless 'mem' of @projectObjList[scope]
      return
    children = @projectObjList[scope]['mem']
    currVis = 1
    if 'vis' of @projectObjList[scope]
      currVis = parseInt(@projectObjList[scope]['vis'])
    for child in children
      if prefix?
        unless child.startsWith(prefix)
          continue
      if onlyList.length > 0
        if onlyList.indexOf(child) == -1
          continue
      childKey = scope+'::'+child
      if childKey of @projectObjList
        if 'vis' of @projectObjList[childKey]
          if parseInt(@projectObjList[childKey]['vis']) + currVis < 0
            continue
        else
          if currVis < 0
            continue
        if @projectObjList[childKey]['type'] == 'copy'
          @resolveInterface(childKey, scope)
          repName = @projectObjList[childKey]['name']
          for copyKey in @projectObjList[childKey]['res_mem']
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
    if 'in_mem' of @projectObjList[scope]
      for childKey in @projectObjList[scope]['in_mem']
        completions.push(@buildCompletion(@projectObjList[childKey]))
    return completions

  resolveInterface: (intObjKey, scope) ->
    if 'res_mem' of @projectObjList[intObjKey]
      return
    resolvedChildren = []
    children = @projectObjList[intObjKey]['mem']
    for copyKey in children
      resolvedScope = @findInScope(scope, copyKey)
      if resolvedScope?
        resolvedChildren.push(resolvedScope+"::"+copyKey)
    @projectObjList[intObjKey]['res_mem'] = resolvedChildren

  resolveLink: (objKey, scope) ->
    unless 'link' of @projectObjList[objKey]
      return
    if 'res_link' of @projectObjList[objKey]
      return
    linkKey = @projectObjList[objKey]['link']
    resolvedScope = @findInScope(scope, linkKey)
    if resolvedScope?
      @projectObjList[objKey]['res_link'] = resolvedScope+"::"+linkKey

  addChild: (scopeKey, childKey) ->
    if 'chld' of @projectObjList[scopeKey]
      if @projectObjList[scopeKey]['chld'].indexOf(childKey) == -1
        @projectObjList[scopeKey]['chld'].push(childKey)
    else
      @projectObjList[scopeKey]['chld'] = [childKey]

  resetInherit: (classObj) ->
    if 'in_mem' of classObj
      delete classObj['in_mem']
    if 'res_parent' of classObj
      delete classObj['res_parent']
    if 'chld' of classObj
      for childKey of classObj['chld']
        childObj =  @projectObjList[childKey]
        if childObj?
          @resetInherit(childObj)

  resolveIherited: (scope) ->
    classObj = @projectObjList[scope]
    if 'in_mem' of classObj
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
      @addChild(parentKey, scope)
      @resolveIherited(parentKey)
      #
      @projectObjList[scope]['in_mem'] = []
      if 'mem' of @projectObjList[scope]
        classChildren = @projectObjList[scope]['mem']
      else
        classChildren = []
      if 'mem' of @projectObjList[parentKey]
        for childKey in @projectObjList[parentKey]['mem']
          if classChildren.indexOf(childKey) == -1
            @projectObjList[scope]['in_mem'].push(parentKey+'::'+childKey)
      if 'in_mem' of @projectObjList[parentKey]
        for childKey in @projectObjList[parentKey]['in_mem']
          childName = childKey.split('::').pop()
          if classChildren.indexOf(childName) == -1
            @projectObjList[scope]['in_mem'].push(childKey)
    return

  buildCompletion: (suggestion, repName=null, stripArg=false) ->
    name = suggestion['name']
    if repName?
      name = repName
    mods = @getModifiers(suggestion)
    if 'args' of suggestion
      argStr = suggestion['args']
      if stripArg
        i1 = argStr.indexOf(',')
        if i1 > -1
          argStr = argStr.substring(i1+1).trim()
        else
          argStr = ''
      type: suggestion['type']
      snippet: name + "(" + argStr + ")"
      leftLabel: @descList[suggestion['desc']]+mods
    else
      type: suggestion['type']
      text: name
      leftLabel: @descList[suggestion['desc']]
      description: mods
    #rightLabel: 'My Provider'

  getModifiers: (suggestion) ->
    modList = []
    if 'mods' of suggestion
      for mod in suggestion['mods']
        switch mod
          when 1 then modList.push("POINTER")
          when 2 then modList.push("ALLOCATABLE")
    return modList.join(', ')

  testPass: (obj) ->
    if 'mods' of obj
      ind = obj['mods'].indexOf(6)
      if ind != -1
        return false
    return true
