{Point} = require 'atom'

AbstractProvider = require './AbstractProvider'

View = require './ConstructorGenerationProvider/View'

TypeHelper = require './Utility/TypeHelper'
DocblockBuilder = require './Utility/DocblockBuilder'
FunctionBuilder = require './Utility/FunctionBuilder'

module.exports =

##*
# Provides docblock generation and maintenance capabilities.
##
class DocblockProvider extends AbstractProvider
    ###*
     * The view that allows the user to select the properties to add to the constructor as parameters.
    ###
    selectionView: null

    ###*
     * Aids in building functions.
    ###
    functionBuilder: null

    ###*
     * The docblock builder.
    ###
    docblockBuilder: null

    ###*
     * The type helper.
    ###
    typeHelper: null

    ###*
     * @inheritdoc
    ###
    activate: (service) ->
        super(service)

        @selectionView = new View(@onConfirm.bind(this), @onCancel.bind(this))
        @selectionView.setLoading('Loading class information...')
        @selectionView.setEmptyMessage('No properties found.')

        @typeHelper = new TypeHelper()
        @functionBuilder = new FunctionBuilder()
        @docblockBuilder = new DocblockBuilder()

    ###*
     * @inheritdoc
    ###
    deactivate: () ->
        super()

        if @typeHelper
            @typeHelper = null

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

                return @getIntentions(textEditor, bufferPosition)
        }]

    ###*
     * @param {TextEditor} editor
     * @param {Point}      triggerPosition
    ###
    getIntentions: (editor, triggerPosition) ->
        successHandler = (currentClassName) =>
            return [] if not currentClassName?

            nestedSuccessHandler = (classInfo) =>
                return [] if not classInfo?
                return [] if '__construct' of classInfo.methods and
                             classInfo.methods['__construct'].declaringClass.name == classInfo.name

                return [{
                    priority : 100
                    icon     : 'gear'
                    title    : 'Generate Constructor'

                    selected : () =>
                        items = []
                        promises = []

                        localTypesResolvedHandler = (results) =>
                            resultIndex = 0

                            for item in items
                                for type in item.types
                                    type.type = results[resultIndex++]

                            zeroBasedStartLine = classInfo.startLine - 1

                            tabText = editor.getTabText()
                            indentationLevel = editor.indentationForBufferRow(triggerPosition.row)

                            @generateConstructor(
                                editor,
                                triggerPosition,
                                items,
                                tabText,
                                indentationLevel,
                                atom.config.get('editor.preferredLineLength', editor.getLastCursor().getScopeDescriptor())
                            )

                        if classInfo.properties.length == 0
                            localTypesResolvedHandler([])

                        else
                            # Ensure all types are localized to the use statements of this file, the original types will be
                            # relative to the original file (which may not be the same). The FQCN works but is long and
                            # there may be a local use statement that can be used to shorten it.
                            for name, property of classInfo.properties
                                items.push({
                                    name  : name
                                    types : property.types
                                })

                                for type in property.types
                                    if @typeHelper.isClassType(type.fqcn)
                                        promises.push @service.localizeType(
                                            editor.getPath(),
                                            triggerPosition.row + 1,
                                            type.fqcn
                                        )

                                    else
                                        promises.push Promise.resolve(type.fqcn)

                            Promise.all(promises).then(localTypesResolvedHandler, failureHandler)
                }]

            return @service.getClassInfo(currentClassName).then(nestedSuccessHandler, failureHandler)

        failureHandler = () ->
            return []

        return @service.determineCurrentClassName(editor, triggerPosition).then(successHandler, failureHandler)

    ###*
     * @param {TextEditor} editor
     * @param {Point}      triggerPosition
     * @param {Array}      items
     * @param {String}     tabText
     * @param {Number}     indentationLevel
     * @param {Number}     maxLineLength
    ###
    generateConstructor: (editor, triggerPosition, items, tabText, indentationLevel, maxLineLength) ->
        metadata = {
            editor           : editor
            position         : triggerPosition
            tabText          : tabText
            indentationLevel : indentationLevel
            maxLineLength    : maxLineLength
        }

        if items.length > 0
            @selectionView.setItems(items)
            @selectionView.setMetadata(metadata)
            @selectionView.storeFocusedElement()
            @selectionView.present()

        else
            @onConfirm([], metadata)

    ###*
     * Called when the selection of properties is cancelled.
     *
     * @param {Object|null} metadata
    ###
    onCancel: (metadata) ->

    ###*
     * Called when the selection of properties is confirmed.
     *
     * @param {array}       selectedItems
     * @param {Object|null} metadata
    ###
    onConfirm: (selectedItems, metadata) ->
        statements = []
        parameters = []
        docblockParameters = []

        enablePhp7Support = if @getCurrentProjectPhpVersion() >= 7.0 then true else false

        for item in selectedItems
            typeSpecification = @typeHelper.buildTypeSpecificationFromTypeArray(item.types)

            parameterTypeHint = @typeHelper.getTypeHintForTypeSpecification(typeSpecification, enablePhp7Support)

            parameterType = if parameterTypeHint? then parameterTypeHint.typeHint else null
            defaultValue  = if parameterTypeHint? and parameterTypeHint.isNullable then 'null' else null

            parameters.push({
                name         : '$' + item.name
                typeHint     : parameterType
                defaultValue : defaultValue
            })

            docblockParameters.push({
                name : '$' + item.name
                type : if item.types.length > 0 then typeSpecification else 'mixed'
            })

            statements.push("$this->#{item.name} = $#{item.name};")

        if statements.length == 0
            statements.push('')

        functionText = @functionBuilder
            .makePublic()
            .setIsStatic(false)
            .setIsAbstract(false)
            .setName('__construct')
            .setReturnType(null)
            .setParameters(parameters)
            .setStatements(statements)
            .setTabText(metadata.tabText)
            .setIndentationLevel(metadata.indentationLevel)
            .setMaxLineLength(metadata.maxLineLength)
            .build()

        docblockText = @docblockBuilder.buildForMethod(
            docblockParameters,
            null,
            false,
            metadata.tabText.repeat(metadata.indentationLevel)
        )

        text = docblockText.trimLeft() + functionText

        metadata.editor.getBuffer().insert(metadata.position, text)
