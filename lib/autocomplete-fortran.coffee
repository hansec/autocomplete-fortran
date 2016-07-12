{CompositeDisposable,File} = require 'atom'

module.exports =
  config:
    pythonPath:
      type: 'string'
      default: '/usr/bin/python'
      order: 1
      title: 'Python Executable Path'
      description: "Optional path to python executable."
    minPrefix:
      type: 'integer'
      default: 2
      order: 2
      title: 'Minimum word length'
      description: "Only autocomplete when you have typed at least this many characters. Note: autocomplete is always active for user-defined type fields."
    preserveCase:
      type: 'boolean'
      default: true
      order: 3
      title: 'Preserve completion case'
      description: "Preserve case of suggestions from their defintion when inserting completions. Otherwise all suggestions will be lowercase."
    useSnippets:
      type: 'boolean'
      default: true
      order: 3
      title: 'Use argument snippets'
      description: "Use snippets for function/subroutine arguments. See: https://github.com/atom/snippets for more information."
  provider: null

  activate: ->
    #console.log 'Activated AC-Fortran!'
    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable
    # Register command that rebuilds index
    @subscriptions.add atom.commands.add 'atom-workspace',
      'autocomplete-fortran:rebuild': => @rebuild()
    @subscriptions.add atom.commands.add 'atom-workspace',
      'autocomplete-fortran:saveIndex': => @saveIndex()
    @subscriptions.add atom.commands.add "atom-text-editor",
      'autocomplete-fortran:go-declaration': (e)=> @goDeclaration atom.workspace.getActiveTextEditor(),e

  deactivate: ->
    @subscriptions.dispose()
    @provider = null

  provide: ->
    unless @provider?
      FortranProvider = require('./fortran-provider')
      @provider = new FortranProvider()
    @provider

  rebuild: ()->
    #console.log "Rebuild triggered"
    if @provider?
      @provider.rebuildIndex()

  goDeclaration: (editor, e)->
    editor.selectWordsContainingCursors()
    varWord = editor.getSelectedText()
    bufferRange = editor.getSelectedBufferRange()
    defPos = @provider.goToDef(varWord, editor, bufferRange.end)
    #console.log defPos
    if defPos?
      splitInfo = defPos.split(":")
      fileName = splitInfo[0]
      lineRef = splitInfo[1]
      f = new File fileName
      f.exists().then (result) ->
        atom.workspace.open fileName, {initialLine:lineRef-1, initialColumn:0} if result
    else
      atom.notifications?.addWarning("Could not find definition: '#{varWord}'", {
        dismissable: true
      })

  saveIndex: () ->
    @provider.saveIndex()
