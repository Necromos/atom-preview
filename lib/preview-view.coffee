path = require 'path'
{$, $$$, ScrollView, EditorView} = require 'atom'
_ = require 'underscore-plus'
renderers = require './renderer'

module.exports =
class PreviewView extends ScrollView
  atom.deserializers.add(PreviewView)

  @deserialize: (state) ->
    new PreviewView(state)

  @content: ->
    @div
      class: 'preview-container native-key-bindings'
      tabindex: -1
      =>
        @div
          outlet: 'codeBlock'
        @div
          outlet: 'message'

  initialize: ->
    super

    # Update on Tab Change
    atom.workspaceView.on \
    'pane-container:active-pane-item-changed', @handleTabChanges

    # Update on font-size change
    atom.config.observe 'editor.fontSize', () =>
      @changeHandler()

    # Setup debounced renderer
    atom.config.observe 'preview.refreshDebouncePeriod', \
    (wait) =>
      # console.log "update debounce to #{wait} ms"
      @debouncedRenderHTMLCode = _.debounce @renderHTMLCode.bind(@), wait

  serialize: ->
    deserializer: 'PreviewView'
    filePath: @getPath()
    editorId: @editorId

  destroy: ->
    @unsubscribe()
    atom.workspaceView.off \
    'pane-container:active-pane-item-changed', @handleTabChanges

  subscribeToFilePath: (filePath) ->
    @trigger 'title-changed'
    @handleEvents()
    @renderHTML()

  resolveEditor: (editorId) ->
    resolve = =>
      @editor = @editorForId(editorId)

      if @editor?
        @trigger 'title-changed' if @editor?
        @handleEvents()
      else
        # The editor this preview was created for has been closed so close
        # this preview since a preview cannot be rendered without an editor
        @parents('.pane').view()?.destroyItem(this)

    if atom.workspace?
      resolve()
    else
      @subscribe atom.packages.once 'activated', =>
        resolve()
        @renderHTML()

  editorForId: (editorId) ->
    for editor in atom.workspace.getEditors()
      return editor if editor.id?.toString() is editorId.toString()
    null

  handleTabChanges: =>
    updateOnTabChange =
      atom.config.get 'preview.updateOnTabChange'
    if updateOnTabChange
      currEditor = atom.workspace.getActiveEditor()
      if currEditor?
        # Stop watching for events on current Editor
        @unsubscribe()
        # Switch to new editor
        @editor = currEditor
        @editorId = @editor.id
        # Start watching editors on new editor
        @handleEvents()
        # Trigger update
        @changeHandler()

  handleEvents: () ->
    if @editor?
      @subscribe @editor.getBuffer(), \
      'contents-modified', @changeHandler
      @subscribe @editor, 'path-changed', => @trigger 'title-changed'

  changeHandler: () =>
    @renderHTML()
    pane = atom.workspace.paneForUri @getUri()
    if pane? and pane isnt atom.workspace.getActivePane()
      pane.activateItem @

  renderHTML: () ->
    if @editor?
      if @text() is ""
        @forceRenderHTML()
      else
        @debouncedRenderHTMLCode()

  forceRenderHTML: () ->
    if @editor?
      @renderHTMLCode()

  renderHTMLCode: () =>
    @showLoading()
    # Update Title
    @trigger 'title-changed'
    # Create Callback
    callback = (error, result) =>
      outLang = renderer.lang()
      grammar = atom.syntax.selectGrammar("source.#{outLang}", result)
      # Get codeBlock
      codeBlock = @codeBlock.find('pre')
      if codeBlock.length is 0
        codeBlock = $('<pre/>')
        @codeBlock.append(codeBlock)
      # Reset codeBlock
      codeBlock.empty()
      codeBlock.addClass('editor-colors')
      # Render the JavaScript as HTML with syntax Highlighting
      htmlEolInvisibles = ''
      for tokens in grammar.tokenizeLines(result).slice(0, -1)
        lineText = _.pluck(tokens, 'value').join('')
        codeBlock.append \
        EditorView.buildLineHtml {tokens, text: lineText, htmlEolInvisibles}
      # Clear message display
      @message.empty()
      # Display the new rendered HTML
      @trigger 'preview:html-changed'
      # Set font-size from Editor to the Preview
      fontSize = atom.config.get('editor.fontSize')
      if fontSize?
        codeBlock.css('font-size', fontSize)
    # Start preview processing
    text = @editor.getText()
    try
      grammar = @editor.getGrammar().name
      renderer = renderers[grammar]
      if not text?
        return @showError new Error "Nothing to render."
      if renderer?
        renderer.render text, callback
      else
        return @showError(new Error \
        "Can not find renderer for grammar #{grammar}.")
    catch e
      return @showError e


  syncScroll: ->
    console.log 'Sync scroll'
    editorView = atom.workspaceView.getActiveView()
    if editorView.getEditor?() is @editor
      scrollView = editorView.scrollView
      height = scrollView[0].scrollHeight
      y = scrollView.scrollTop()


  getTitle: ->
    if @editor?
      "#{@editor.getTitle()} preview"
    else
      "Preview"

  getUri: ->
    "preview://editor"

  getPath: ->
    if @editor?
      @editor.getPath()

  showError: (result) ->
    failureMessage = result?.message

    @codeBlock.empty()
    @message.html $$$ ->
      @div
        class: 'preview-spinner'
        style: 'text-align: center'
        =>
          @span
            class: 'loading loading-spinner-large inline-block'
          @div
            class: 'text-highlight',
            'Previewing Failed\u2026'
            =>
              @div
                class: 'text-error'
                failureMessage if failureMessage?
          @div
            class: 'text-warning'
            result?.stack

  showLoading: ->

    @codeBlock.empty()
    @message.html $$$ ->
      @div
        class: 'preview-spinner'
        style: 'text-align: center'
        =>
          @span
            class: 'loading loading-spinner-large inline-block'
          @div
            class: 'text-highlight',
            'Loading HTML Preview\u2026'
