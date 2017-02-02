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
  pythonValid: -1
  parserPath: ''
  minPrefix: 2
  preserveCase: true
  useSnippets: true
  firstRun: true
  indexReady: false
  globalUpToDate: true
  lastFile: ''
  lastRow: -1

  fileObjInd: { }
  fileObjLists: { }
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
    @preserveCase = atom.config.get('autocomplete-fortran.preserveCase')
    @useSnippets = atom.config.get('autocomplete-fortran.useSnippets')
    @saveWatchers = new CompositeDisposable
    @workspaceWatcher = atom.workspace.observeTextEditors((editor) => @setupEditors(editor))
    @checkPythonPath()

  destructor: () ->
    if @workspaceWatcher?
      @workspaceWatcher.dispose()
    if @saveWatchers?
      @saveWatchers.dispose()

  checkPythonPath: () ->
    command = @pythonPath
    stdOutput = ""
    errOutput = ""
    args = ["-V"]
    stdout = (output) => stdOutput = output
    stderr = (output) => errOutput = output
    exit = (code) =>
      if @pythonValid == -1
        unless code == 0
          @pythonValid = 0
        if errOutput.indexOf('is not recognized as an internal or external') > -1
          @pythonValid = 0
      if @pythonValid == -1
        @pythonValid = 1
      else
        console.log '[ac-fortran] Python check failed'
        console.log '[ac-fortran]',errOutput
    bufferedProcess = new BufferedProcess({command, args, stdout, stderr, exit})
    bufferedProcess.onWillThrowError ({error, handle}) =>
      if error.code is 'ENOENT' and error.syscall.indexOf('spawn') is 0
        @pythonValid = 0
        console.log '[ac-fortran] Python check failed'
        console.log '[ac-fortran]',error
        handle()
      else
        throw error

  setupEditors: (editor) ->
    scopeDesc = editor.getRootScopeDescriptor().getScopesArray()
    if scopeDesc[0]?.indexOf('fortran') > -1
      @saveWatchers.add editor.onDidSave((event) => @fileUpdateSave(event))

  fileUpdateSave: (event) ->
    if @pythonValid < 1
      if @pythonValid == 0
        @addError("Python path error", "Disabling FORTRAN autocompletion")
        @pythonValid = -2
      return
    fileRef = @modFiles.indexOf(event.path)
    if fileRef > -1
      @fileUpdate(event.path, true)

  rebuildIndex: () ->
    # Reset index
    @indexReady = false
    @globalUpToDate = true
    @lastFile = ''
    @lastRow = -1
    @modDirs = []
    @modFiles = []
    @fileIndexed = []
    @fileObjInd = { }
    @fileObjLists = { }
    @globalObjInd = []
    @projectObjList = { }
    @descList = []
    # Build index
    @findModFiles()
    @filesUpdate(@modFiles)

  checkIndex: () ->
    if @indexReady
      return true
    for isIndexed in @fileIndexed
      unless isIndexed
        return false
    @indexReady = true
    return true

  addInfo: (info, detail=null) ->
    if detail?
      atom.notifications?.addInfo("ac-fortran: #{info}", {detail: detail})
    else
      atom.notifications?.addInfo("ac-fortran: #{info}")

  addError: (info, detail=null) ->
    if detail?
      atom.notifications?.addError("ac-fortran: #{info}", {detail: detail})
    else
      atom.notifications?.addError("ac-fortran: #{info}")

  notifyIndexPending: (operation) ->
    atom.notifications?.addWarning("Could not complete operation: #{operation}", {
      detail: 'Indexing pending',
      dismissable: true
    })

  findModFiles: ()->
    freeRegex = /[a-z0-9_]*\.F(90|95|03|08)$/i # f90,F90,f95,F95,f03,F03,f08,F08
    fixedRegex = /[a-z0-9_]*\.F(77|OR|PP)?$/i # f,F,f77,F77,for,FOR,fpp,FPP
    projectDirs = atom.project.getPaths()
    @modDirs = projectDirs
    @exclPaths = []
    extPaths = []
    for projDir in projectDirs
      settingPath = path.join(projDir, '.ac_fortran')
      try
        fs.accessSync(settingPath, fs.R_OK)
        fs.openSync(settingPath, 'r+')
        result = fs.readFileSync(settingPath)
        try
          configOptions = JSON.parse(result)
        catch
          @addError("Error reading project settings", "path #{settingPath}")
          continue
        if 'excl_paths' of configOptions
          for exclPath in configOptions['excl_paths']
            @exclPaths.push(path.join(projDir, exclPath))
        if 'mod_dirs' of configOptions
          @modDirs = []
          for modDir in configOptions['mod_dirs']
            @modDirs.push(path.join(projDir, modDir))
        if 'ext_index' of configOptions
          for relPath in configOptions['ext_index']
            indexPath = path.join(projDir, relPath)
            try
              fs.accessSync(indexPath, fs.R_OK)
              fs.openSync(indexPath, 'r+')
              result = fs.readFileSync(indexPath)
              extIndex = JSON.parse(result)
              objListing = extIndex['obj']
              descListing = extIndex['descs']
              for key of objListing
                @projectObjList[key] = objListing[key]
                obj = @projectObjList[key]
                descInd = obj['desc']
                descStr = descListing[descInd]
                if descStr?
                  descIndex = @descList.indexOf(descStr)
                  if descIndex == -1
                    @descList.push(descStr)
                    obj['desc'] = @descList.length-1
                  else
                    obj['desc'] = descIndex
              extPaths.push("#{relPath}")
            catch
              @addError("Cannot read external index file", "path #{relPath}")
    if extPaths.length > 0
      @addInfo("Added external index files", extPaths.join('\n'))
    for modDir in @modDirs
      try
        files = fs.readdirSync(modDir)
      catch
        atom.notifications?.addWarning("Warning: During indexing specified module directory cannot be read", {
          detail: "Directory '#{modDir}' will be skipped",
          dismissable: true
        })
        continue
      for file in files
        if file.match(freeRegex) or file.match(fixedRegex)
          filePath = path.join(modDir, file)
          if @exclPaths.indexOf(filePath) == -1
            @modFiles.push(filePath)
            @fileIndexed.push(false)

  filesUpdate: (filePaths, closeScopes=false)->
    fixedRegex = /[a-z0-9_]*\.F(77|OR|PP)?$/i # f,F,f77,F77,for,FOR,fpp,FPP
    command = @pythonPath
    #
    fixedBatch = []
    freeBatch = []
    for filePath in filePaths
      if filePath.match(fixedRegex)
        fixedBatch.push(filePath)
      else
        freeBatch.push(filePath)
    #
    if fixedBatch.length > 0
      fixedFilePaths = fixedBatch.join(',')
      new Promise (resolve) =>
        allOutput = []
        args = [@parserPath, "--files=#{fixedFilePaths}", "--fixed"]
        if closeScopes
          args.push("--close_scopes")
        stdout = (output) => allOutput.push(output)
        stderr = (output) => console.log output
        exit = (code) => resolve(@handleParserResults(allOutput.join(''), code, fixedBatch))
        fixedBufferedProcess = new BufferedProcess({command, args, stdout, stderr, exit})
    #
    if freeBatch.length > 0
      freeFilePaths = freeBatch.join(',')
      new Promise (resolve) =>
        allOutput = []
        args = [@parserPath, "--files=#{freeFilePaths}"]
        if closeScopes
          args.push("--close_scopes")
        stdout = (output) => allOutput.push(output)
        stderr = (output) => console.log output
        exit = (code) => resolve(@handleParserResults(allOutput.join(''), code, freeBatch))
        freeBufferedProcess = new BufferedProcess({command, args, stdout, stderr, exit})

  fileUpdate: (filePath, closeScopes=false)->
    fixedRegex = /[a-z0-9_]*\.F(77|OR|PP)?$/i # f,F,f77,F77,for,FOR,fpp,FPP
    command = @pythonPath
    args = [@parserPath,"--files=#{filePath}"]
    if filePath.match(fixedRegex)
      args.push("--fixed")
    if closeScopes
      args.push("--close_scopes")
    #
    new Promise (resolve) =>
      allOutput = []
      stdout = (output) => allOutput.push(output)
      stderr = (output) => console.log output
      exit = (code) => resolve(@handleParserResult(allOutput.join('\n'), code, filePath))
      bufferedProcess = new BufferedProcess({command, args, stdout, stderr, exit})

  localUpdate: (editor, row)->
    fixedRegex = /[a-z0-9_]*\.F(77|OR|PP)?$/i # f,F,f77,F77,for,FOR,fpp,FPP
    filePath = editor.getPath()
    command = @pythonPath
    args = [@parserPath,"-s"]
    if filePath.match(fixedRegex)
      args.push("--fixed")
    #
    new Promise (resolve) =>
      allOutput = []
      stdout = (output) => allOutput.push(output)
      stderr = (output) => console.log output
      exit = (code) => resolve(@handleParserResult(allOutput.join('\n'), code, filePath))
      bufferedProcess = new BufferedProcess({command, args, stdout, stderr, exit})
      bufferedProcess.process.stdin.setEncoding = 'utf-8';
      bufferedProcess.process.stdin.write(editor.getText())
      bufferedProcess.process.stdin.end()

  handleParserResults: (results,returnCode,filePaths) ->
    if returnCode is not 0
      return
    resultsSplit = results.split('\n')
    nResults = resultsSplit.length - 1
    nFiles = filePaths.length
    if nResults != nFiles
      console.log 'Error parsing files: # of files and results does not match', nResults, nFiles
      return
    for i in [0..nFiles-1]
      @handleParserResult(resultsSplit[i],returnCode,filePaths[i])

  handleParserResult: (result,returnCode,filePath) ->
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
    oldObjList = @fileObjLists[filePath]
    @fileObjLists[filePath] = []
    for key of fileAST['objs']
      @fileObjLists[filePath].push(key)
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
    # Remove old objects
    if oldObjList?
      for key in oldObjList
        unless key of fileAST['objs']
          delete @projectObjList[key]
    @fileObjInd[filePath] = fileAST['scopes']
    @fileIndexed[fileRef] = true
    @globalUpToDate = false

  updateGlobalIndex: () ->
    if @globalUpToDate
      return
    @globalObjInd = []
    for key of @projectObjList
      if not key.match(/::/)
        @globalObjInd.push(key)

  getSuggestions: ({editor, bufferPosition, prefix, activatedManually}) ->
    if @pythonValid < 1
      if @pythonValid == 0
        @addError("Python path error", "Disabling FORTRAN autocompletion")
        @pythonValid = -2
      return
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
    suggestions = []
    @updateGlobalIndex()
    if prefix
      prefixLower = prefix.toLowerCase()
      fullLine = @getFullLine(editor, bufferPosition)
      lineContext = @getLineContext(fullLine)
      if lineContext == 2
        return completions
      if lineContext == 1
        suggestions = @getUseSuggestion(fullLine, prefixLower)
        return @buildCompletionList(suggestions, lineContext)
      lineScopes = @getLineScopes(editor, bufferPosition)
      cursorScope = @getClassScope(fullLine, lineScopes)
      if cursorScope?
        suggestions = @addChildren(cursorScope, suggestions, prefixLower, [])
        return @buildCompletionList(suggestions, lineContext)
      if prefix.length < @minPrefix and not activatedManually
        return completions
      for key in @globalObjInd when (@projectObjList[key]['name'].toLowerCase().startsWith(prefixLower))
        if @projectObjList[key]['type'] == 1
          continue
        suggestions.push(key)
      #
      usedMod = { }
      for lineScope in lineScopes
        suggestions = @addChildren(lineScope, suggestions, prefixLower, [])
        usedMod = @getUseSearches(lineScope, usedMod, [])
      for useMod of usedMod
        suggestions = @addPublicChildren(useMod, suggestions, prefixLower, usedMod[useMod])
      completions = @buildCompletionList(suggestions, lineContext)
    else
      line = editor.getTextInRange([[bufferPosition.row, 0], bufferPosition])
      unless line.endsWith('%')
        return completions
      fullLine = @getFullLine(editor, bufferPosition)
      lineContext = @getLineContext(fullLine)
      lineScopes = @getLineScopes(editor, bufferPosition)
      cursorScope = @getClassScope(fullLine, lineScopes)
      if cursorScope?
        suggestions = @addChildren(cursorScope, suggestions, prefixLower, [])
        return @buildCompletionList(suggestions,lineContext)
    return completions

  saveIndex: () ->
    # Build index on first run
    if @firstRun
      @rebuildIndex()
      @firstRun = false
    unless @checkIndex()
      @notifyIndexPending('Save Index')
      return
    removalList = []
    for key of @projectObjList
      obj = @projectObjList[key]
      type = obj['type']
      if type == 2 or type == 3
        memList = obj['mem']
        if memList?
          for member in memList
            removalList.push(key+'::'+member.toLowerCase())
        delete obj['mem']
    for key in removalList
      delete @projectObjList[key]
    newDescList = []
    newDescs = []
    for key of @projectObjList
      obj = @projectObjList[key]
      if obj['type'] == 7
        @resolveInterface(key)
      @resolveIherited(key)
      delete obj['fdef']
      delete obj['file']
      delete obj['fbound']
      desInd = obj['desc']
      descIndex = newDescList.indexOf(desInd)
      if descIndex == -1
        newDescList.push(desInd)
        newDescs.push(@descList[desInd])
        obj['desc'] = newDescList.length-1
      else
        obj['desc'] = descIndex
    outObj = {'obj': @projectObjList, 'descs': newDescs}
    projectDirs = atom.project.getPaths()
    outputPath = path.join(projectDirs[0], 'ac_fortran_index.json')
    fd = fs.openSync(outputPath, 'w+')
    fs.writeSync(fd, JSON.stringify(outObj))
    fs.closeSync(fd)
    @rebuildIndex()

  goToDef: (word, editor, bufferPosition) ->
    # Build index on first run
    if @firstRun
      @rebuildIndex()
      @firstRun = false
    @localUpdate(editor, bufferPosition.row)
    unless @checkIndex()
      @notifyIndexPending('Go To Definition')
      return
    @updateGlobalIndex()
    wordLower = word.toLowerCase()
    lineScopes = @getLineScopes(editor, bufferPosition)
    # Look up class tree
    fullLine = @getFullLine(editor, bufferPosition)
    cursorScope = @getClassScope(fullLine, lineScopes)
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

  getUseSuggestion: (line, prefixLower) ->
    useRegex = /^[ \t]*use[ \t]+/i
    wordRegex = /[a-z0-9_]+/gi
    suggestions = []
    if line.match(useRegex)?
      unless prefixLower.match(wordRegex)?
        prefixLower = ""
      matches = line.match(wordRegex)
      if matches.length == 2
        if prefixLower?
          for key in @globalObjInd when (@projectObjList[key]['name'].toLowerCase().startsWith(prefixLower))
            if @projectObjList[key]['type'] != 1
              continue
            suggestions.push(key)
        else
          for key in @globalObjInd
            suggestions.push(key)
      else if matches.length > 2
        modName = matches[1]
        suggestions = @addPublicChildren(modName, suggestions, prefixLower, [])
    return suggestions # Unknown enable everything!!!!

  getFullLine: (editor, bufferPosition) ->
    fixedRegex = /[a-z0-9_]*\.F(77|OR|PP)?$/i # f,F,f77,F77,for,FOR,fpp,FPP
    fixedCommRegex = /^     [\S]/i
    freeCommRegex = /&[ \t]*$/i
    line = editor.getTextInRange([[bufferPosition.row, 0], bufferPosition])
    #
    fixedForm = false
    if editor.getPath().match(fixedRegex)
      fixedForm = true
    pRow = bufferPosition.row - 1
    while pRow >= 0
      pLine = editor.lineTextForBufferRow(pRow)
      pLine = pLine.split('!')[0]
      if fixedForm
        unless line.match(fixedCommRegex)
          break
      else
        unless pLine.match(freeCommRegex)
          break
      line = pLine.split('&')[0] + line
      pRow = pRow - 1
    return line

  getLineContext: (line) ->
    useRegex = /^[ \t]*USE[ \t]/i
    subDefRegex = /^[ \t]*(PURE|ELEMENTAL|RECURSIVE)*[ \t]*(MODULE|PROGRAM|SUBROUTINE|FUNCTION)[ \t]/i
    typeDefRegex = /^[ \t]*(CLASS|TYPE)[ \t]*(IS)?[ \t]*\(/i
    callRegex = /^[ \t]*CALL[ \t]+[a-z0-9_%]*$/i
    deallocRegex = /^[ \t]*DEALLOCATE[ \t]*\(/i
    nullifyRegex = /^[ \t]*NULLIFY[ \t]*\(/i
    if line.match(callRegex)?
      return 4
    if line.match(deallocRegex)?
      return 5
    if line.match(nullifyRegex)?
      return 6
    if line.match(useRegex)?
      return 1
    if line.match(useRegex)?
      return 2
    if line.match(typeDefRegex)?
      return 3
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
    scopeObj = @projectObjList[scope]
    unless scopeObj?
      return null
    # Check inherited
    if 'in_mem' of scopeObj
      for childKey in scopeObj['in_mem']
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

  getClassScope: (line, currScopes) ->
    typeDerefCheck = /%/i
    objBreakReg = /[\/\-(.,+*<>=$:]/ig
    parenRepReg = /\((.+)\)/ig
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
            if @projectObjList[varKey]['type'] == 6
              varDefName = @getVarType(varKey)
              iLast = containingScope.lastIndexOf("::")
              typeScope = containingScope
              if iLast > -1
                typeScope = containingScope.substring(0,iLast)
              containingScope = @findInScope(typeScope, varDefName)
              searchScope = containingScope + '::' + varDefName
          else
            return null
        else
          for currScope in currScopes
            @resolveIherited(currScope)
            containingScope = @findInScope(currScope, varNameLower)
            if containingScope?
              varKey = containingScope + "::" + varNameLower
              if @projectObjList[varKey]['type'] == 6
                varDefName = @getVarType(varKey)
                iLast = containingScope.lastIndexOf("::")
                typeScope = containingScope
                if iLast > -1
                  typeScope = containingScope.substring(0,iLast)
                containingScope = @findInScope(typeScope, varDefName)
                searchScope = containingScope + '::' + varDefName
              break
    return searchScope # Unknown enable everything!!!!

  addChildren: (scope, completions, prefix, onlyList) ->
    scopeObj = @projectObjList[scope]
    unless scopeObj?
      return completions
    children = scopeObj['mem']
    unless children?
      return
    for child in children
      childLower = child.toLowerCase()
      if prefix?
        unless childLower.startsWith(prefix)
          continue
      if onlyList.length > 0
        if onlyList.indexOf(childLower) == -1
          continue
      childKey = scope+'::'+childLower
      if childKey of @projectObjList
        completions.push(childKey)
    # Add inherited
    @resolveIherited(scope)
    if 'in_mem' of scopeObj
      for childKey in scopeObj['in_mem']
        completions.push(childKey)
    return completions

  getUseSearches: (scope, modDict, onlyList) ->
    # Process USE STMT (only if no onlyList)
    useList = @projectObjList[scope]['use']
    if useList?
      for useMod in useList
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
    scopeObj = @projectObjList[scope]
    unless scopeObj?
      return completions
    children = scopeObj['mem']
    unless children?
      return
    currVis = 1
    if 'vis' of scopeObj
      currVis = parseInt(scopeObj['vis'])
    for child in children
      childLower = child.toLowerCase()
      if prefix?
        unless childLower.startsWith(prefix)
          continue
      if onlyList.length > 0
        if onlyList.indexOf(childLower) == -1
          continue
      childKey = scope+'::'+childLower
      childObj = @projectObjList[childKey]
      if childObj?
        if 'vis' of childObj
          if parseInt(childObj['vis']) + currVis < 0
            continue
        else
          if currVis < 0
            continue
        completions.push(childKey)
    # Add inherited
    @resolveIherited(scope)
    if 'in_mem' of scopeObj
      for childKey in scopeObj['in_mem']
        completions.push(childKey)
    return completions

  resolveInterface: (intObjKey) ->
    intObj = @projectObjList[intObjKey]
    if 'res_mem' of intObj
      return
    enclosingScope = @getEnclosingScope(intObjKey)
    unless enclosingScope?
      return
    resolvedChildren = []
    children = intObj['mem']
    for copyKey in children
      resolvedScope = @findInScope(enclosingScope, copyKey)
      if resolvedScope?
        resolvedChildren.push(resolvedScope+"::"+copyKey)
    intObj['res_mem'] = resolvedChildren

  resolveLink: (objKey) ->
    varObj = @projectObjList[objKey]
    linkKey = varObj['link']
    unless linkKey?
      return
    if 'res_link' of varObj
      return
    enclosingScope = @getEnclosingScope(objKey)
    unless enclosingScope?
      return
    resolvedScope = @findInScope(enclosingScope, linkKey)
    if resolvedScope?
      varObj['res_link'] = resolvedScope+"::"+linkKey

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
        classObj['res_parent'] = resolvedScope+"::"+parentName
      else
        return
    # Load from parent class
    parentKey = classObj['res_parent']
    parentObj = @projectObjList[parentKey]
    if parentObj?
      @addChild(parentKey, scope)
      @resolveIherited(parentKey)
      #
      classObj['in_mem'] = []
      if 'mem' of classObj
        classChildren = classObj['mem']
      else
        classChildren = []
      if 'mem' of parentObj
        for childKey in parentObj['mem']
          if classChildren.indexOf(childKey) == -1
            classObj['in_mem'].push(parentKey+'::'+childKey)
      if 'in_mem' of parentObj
        for childKey in parentObj['in_mem']
          childName = childKey.split('::').pop()
          if classChildren.indexOf(childName) == -1
            classObj['in_mem'].push(childKey)
    return

  getEnclosingScope: (objKey) ->
    finalSep = objKey.lastIndexOf('::')
    if finalSep == -1
      return null
    return objKey.substring(0,finalSep)

  buildCompletionList: (suggestions, contextFilter=0) ->
    subTestRegex = /^(TYP|CLA|PRO)/i
    typRegex = /^(TYP|CLA)/i
    completions = []
    for suggestion in suggestions
      compObj = @projectObjList[suggestion]
      if contextFilter == 3 and compObj['type'] != 4
        continue
      if contextFilter == 4
        if compObj['type'] == 3 or compObj['type'] == 4
          continue
        if compObj['type'] == 6
          unless @descList[compObj['desc']].match(subTestRegex)?
            continue
      if contextFilter == 5 or contextFilter == 6
        if compObj['type'] == 6
          modList = compObj['mods']
          isPoint = false
          isAlloc = false
          if modList?
            isPoint = (modList.indexOf(1) > -1)
            if contextFilter == 5
              isAlloc = (modList.indexOf(2) > -1)
          isType = @descList[compObj['desc']].match(typRegex)?
          unless (isPoint or isAlloc or isType)
            continue
        else
          continue
      if compObj['type'] == 7
        @resolveInterface(suggestion)
        repName = compObj['name']
        for copyKey in compObj['res_mem']
          completions.push(@buildCompletion(@projectObjList[copyKey], repName))
      else
        if 'link' of compObj
          @resolveLink(suggestion)
          repName = compObj['name']
          copyKey = compObj['res_link']
          if copyKey?
            doPass = @testPass(compObj)
            completions.push(@buildCompletion(@projectObjList[copyKey], repName, doPass))
          else
            completions.push(@buildCompletion(compObj))
        else
          completions.push(@buildCompletion(compObj))
    #
    if contextFilter == 1
      for completion in completions
        if 'snippet' of completion
          completion['snippet'] = completion['snippet'].split('(')[0]
    return completions

  buildCompletion: (suggestion, repName=null, stripArg=false) ->
    name = suggestion['name']
    if repName?
      name = repName
    mods = @getModifiers(suggestion)
    compObj = {}
    compObj.type = @mapType(suggestion['type'])
    compObj.leftLabel = @descList[suggestion['desc']]
    unless @preserveCase
      name = name.toLowerCase()
    if 'args' of suggestion
      argStr = suggestion['args']
      if @useSnippets
        argList = argStr.split(',')
        argListFinal = []
        i = 0
        for arg in argList
          i += 1
          if stripArg and i == 1
            continue
          i1 = arg.indexOf("=")
          if i1 == -1
            argListFinal.push("${#{i}:#{arg}}")
          else
            argName = arg.substring(0,i1)
            argListFinal.push("#{argName}=${#{i}:#{argName}}")
        argStr = argListFinal.join(',')
      else
        if stripArg
          i1 = argStr.indexOf(',')
          if i1 > -1
            argStr = argStr.substring(i1+1).trim()
          else
            argStr = ''
      unless @preserveCase
        argStr = argStr.toLowerCase()
      compObj.snippet = name + "(" + argStr + ")"
    else
      compObj.text = name
    if mods != ''
      compObj.description = mods
    return compObj
    #rightLabel: 'My Provider'

  mapType: (typeInd) ->
    switch typeInd
      when 1 then return 'module'
      when 2 then return 'method'
      when 3 then return 'function'
      when 4 then return 'class'
      when 5 then return 'interface'
      when 6 then return 'variable'
    return 'unknown'

  getModifiers: (suggestion) ->
    modList = []
    if 'mods' of suggestion
      for mod in suggestion['mods']
        if mod > 20
          ndims = mod-20
          dimStr = "DIMENSION(:"
          if ndims > 1
            for i in [2..ndims]
              dimStr += ",:"
          dimStr += ")"
          modList.push(dimStr)
          continue
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
