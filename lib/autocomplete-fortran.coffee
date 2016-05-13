{CompositeDisposable} = require 'atom'

module.exports =
  config:
    pythonPath:
      type: 'string'
      default: '/usr/bin/python'
      order: 1
      title: 'Python Executable Path'
      description: '''Optional path to python executable.'''
  provider: null

  activate: ->
    console.log 'Activated AC-Fortran!'
    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable
    # Register command that rebuilds index
    @subscriptions.add atom.commands.add 'atom-workspace',
      'autocomplete-fortran:rebuild': => @rebuild()

  deactivate: ->
    @subscriptions.dispose()
    @provider = null

  provide: ->
    unless @provider?
      FortranProvider = require('./fortran-provider')
      @provider = new FortranProvider()
    @provider

  rebuild: ()->
    console.log "Rebuild triggered"
    if @provider?
      @provider.rebuildIndex()
