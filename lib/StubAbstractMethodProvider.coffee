AbstractProvider = require './AbstractProvider'

View = require './StubAbstractMethodProvider/View'

FunctionBuilder = require './Utility/FunctionBuilder'
DocblockBuilder = require './Utility/DocblockBuilder'

module.exports =

##*
# Provides the ability to stub abstract methods.
##
class StubAbstractMethodProvider extends AbstractProvider
    ###*
     * The view that allows the user to select the properties to generate for.
    ###
    selectionView: null

    ###*
     * @type {DocblockBuilder}
    ###
    docblockBuilder: null

    ###*
     * @type {FunctionBuilder}
    ###
    functionBuilder: null

    ###*
     * @inheritdoc
    ###
    activate: (service) ->
        super(service)

        @docblockBuilder = new DocblockBuilder
        @functionBuilder = new FunctionBuilder

        @selectionView = new View(@onConfirm.bind(this), @onCancel.bind(this))
        @selectionView.setLoading('Loading class information...')
        @selectionView.setEmptyMessage('No unimplemented abstract methods found.')

    ###*
     * @inheritdoc
    ###
    deactivate: () ->
        super()

        if @functionBuilder
            @functionBuilder = null

        if @docblockBuilder
            @docblockBuilder = null

        if @selectionView
            @selectionView.destroy()
            @selectionView = null

    ###*
     * @inheritdoc
    ###
    getIntentionProviders: () ->
        return [{
            grammarScopes: ['source.php']
            getIntentions: ({textEditor, bufferPosition}) =>
                return [] if not @getCurrentProjectPhpVersion()?

                return @getStubInterfaceMethodIntentions(textEditor, bufferPosition)
        }]

    ###*
     * @param {TextEditor} editor
     * @param {Point}      triggerPosition
    ###
    getStubInterfaceMethodIntentions: (editor, triggerPosition) ->
        failureHandler = () ->
            return []

        successHandler = (currentClassName) =>
            return [] if not currentClassName

            nestedSuccessHandler = (classInfo) =>
                return [] if not classInfo

                items = []

                for name, method of classInfo.methods
                    data = {
                        name   : name
                        method : method
                    }

                    if method.isAbstract
                        items.push(data)

                return [] if items.length == 0

                @selectionView.setItems(items)

                return [
                    {
                        priority : 100
                        icon     : 'link'
                        title    : 'Stub Unimplemented Abstract Method(s)'

                        selected : () =>
                            @executeStubInterfaceMethods(editor)
                    }
                ]

            return @service.getClassInfo(currentClassName).then(nestedSuccessHandler, failureHandler)

        return @service.determineCurrentClassName(editor, triggerPosition).then(successHandler, failureHandler)

    ###*
     * @param {TextEditor} editor
     * @param {Point}      triggerPosition
    ###
    executeStubInterfaceMethods: (editor) ->
        @selectionView.setMetadata({editor: editor})
        @selectionView.storeFocusedElement()
        @selectionView.present()

    ###*
     * Called when the selection of properties is cancelled.
    ###
    onCancel: (metadata) ->

    ###*
     * Called when the selection of properties is confirmed.
     *
     * @param {array}       selectedItems
     * @param {Object|null} metadata
    ###
    onConfirm: (selectedItems, metadata) ->
        itemOutputs = []

        tabText = metadata.editor.getTabText()
        indentationLevel = metadata.editor.indentationForBufferRow(metadata.editor.getCursorBufferPosition().row)
        maxLineLength = atom.config.get('editor.preferredLineLength', metadata.editor.getLastCursor().getScopeDescriptor())

        for item in selectedItems
            itemOutputs.push(@generateStubForInterfaceMethod(item.method, tabText, indentationLevel, maxLineLength))

        output = itemOutputs.join("\n").trim()

        metadata.editor.insertText(output)

    ###*
     * Generates a stub for the specified selected data.
     *
     * @param {Object} data
     * @param {String} tabText
     * @param {Number} indentationLevel
     * @param {Number} maxLineLength
     *
     * @return {string}
    ###
    generateStubForInterfaceMethod: (data, tabText, indentationLevel, maxLineLength) ->
        statements = [
            "throw new \\LogicException('Not implemented'); // TODO"
        ]

        functionText = @functionBuilder
            .setFromRawMethodData(data)
            .setIsAbstract(false)
            .setStatements(statements)
            .setTabText(tabText)
            .setIndentationLevel(indentationLevel)
            .setMaxLineLength(maxLineLength)
            .build()

        docblockText = @docblockBuilder.buildByLines(['@inheritDoc'], tabText.repeat(indentationLevel))

        return docblockText + functionText
