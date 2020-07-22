#= require ./change

u = up.util
e = up.element

class up.Change.FromContent extends up.Change

  constructor: (options) ->
    up.layer.normalizeOptions(options)
    @layers = up.layer.getAll(options)
    super(options)

  ensurePlansBuilt: ->
    # The actual error message will be produced in preflightTargetNotApplicable()
    # or postFlightTargetNotApplicable(). Here it is only important to signal
    # notApplicable().
    @plans or @buildPlans() or @notApplicable()

  buildPlans: ->
    @plans = []

    fallback = @options.fallback

    # First we seek @options.target in all layers
    for layer in @layers
      @addPlansForTarget(@options.target, { layer })

    if fallback != false

      # Second we seek @options.fallback in all layers
      for layer in @layers
        @addPlansForTarget(fallback, { layer, resetOverlay: true })

      # Third we seek the default target of all layers
      for layer in @layers
        for defaultTarget in @defaultTargets(layer)
          @addPlansForTarget(defaultTarget, { layer, resetOverlay: true })

    if resetTargets = up.fragment.config.resetTargets
      @addPlansForTarget(resetTargets, { layer: up.layer.root, peel: true })

    @plans

  defaultTargets: (layer) ->
    if layer == 'new'
      return up.layer.defaultTargets(@options.mode)
    else
      return layer.defaultTargets()

  addPlansForTarget: (target, variantProps) ->
    for target in u.wrapList(target)
      props = u.merge(@options, variantProps)

      if u.isElementish(target)
        props.target = e.toSelector(target)
      else if u.isString(target)
        props.target = e.resolveSelector(target, props.origin)
      else
        # @buildPlans() might call us with { target: false } or { target: nil }
        # In that case we don't add a plan.
        continue

      if props.layer == 'new'
        change = new up.Change.OpenLayer(props)
        @plans.push(change)
      else
        change = new up.Change.UpdateLayer(props)
        @plans.push(change)

        # Only for existing overlays we open will also attempt to place a new element as the
        # new first child of the layer's root element. This mirrors the behavior that we get when
        # opening a layer: The new element does not need to match anything in the current document.
        if props.resetOverlay && props.layer.isOverlay?()
          change = new up.Change.UpdateLayer(u.merge(props, placement: 'root'))
          @plans.push(change)

  firstDefaultTarget: ->
    if firstLayer = @layers[0]
      @defaultTargets(firstLayer)[0]

  execute: ->
    @buildResponseDoc()

    if @options.saveScroll
      up.viewport.saveScroll()

    # In up.Change.FromURL we already set an X-Up-Title header as options.title.
    # Now that we process an HTML document
    shouldExtractTitle = not (@options.title is false || u.isString(@options.title))
    if shouldExtractTitle && (title = @options.responseDoc.title())
      @options.title = title

    return @seekPlan
      attempt: (plan) -> plan.execute()
      noneApplicable: => @postflightTargetNotApplicable()

  buildResponseDoc: ->
    docOptions = u.pick(@options, ['target', 'content', 'fragment', 'document', 'html'])
    up.legacy.fixKey(docOptions, 'html', 'document')

    # We require this branch for { content: string } or { content: undefined }
    if !docOptions.document
      # ResponseDoc allows to pass innerHTML as { content }, but then it also
      # requires a { target }. If no { target } is given we use the first plan's target.
      docOptions.defaultTarget = @firstDefaultTarget()

    @options.responseDoc = new up.ResponseDoc(docOptions)

    if docOptions.fragment
      # ResponseDoc allows to pass innerHTML as { fragment }, but then it also
      # requires a { target }. We use a target that matches the parsed { fragment }.
      @options.target ||= @options.responseDoc.rootSelector()

  # Returns information about the change that is most likely before the request was dispatched.
  # This might change postflight if the response does not contain the desired target.
  requestAttributes: (opts = {}) ->
    @seekPlan
      attempt: (plan) -> plan.requestAttributes()
      noneApplicable: =>
        opts.optional or @preflightTargetNotApplicable(opts)

  preflightTargetNotApplicable: ->
    if @plans.length
      up.fail("Could not find target in current page (tried selectors %o)", @planTargets())
    else
      @emptyPlans()

  postflightTargetNotApplicable: ->
    if @options.inspectResponse
      toastOpts = { action: { label: 'Open response', callback: @options.inspectResponse } }

    if @plans.length
      up.fail(["Could not find matching targets in current page and server response (tried selectors %o)", @planTargets()], toastOpts)
    else
      @emptyPlans(toastOpts)

  emptyPlans: (toastOpts) ->
    if @layers.length
      up.fail(['No target for change %o', @options], toastOpts)
    else
      # This can happen e.g. if the user tries to replace { layer: 'parent' },
      # but there is no parent layer.
      up.fail(["Layer %o does not exist", @options.layer], toastOpts)

  planTargets: ->
    return u.uniq(u.map(@plans, 'target'))

  seekPlan: (opts) ->
    @ensurePlansBuilt()
    unprintedMessages = []

    for plan in @plans
      try
        return opts.attempt(plan)
      catch error
        if up.error.notApplicable.is(error)
          unprintedMessages.push(error.message)
        else
          # Re-throw any unexpected type of error
          throw error

    # If we're about to explode with a fatal error we print everything that we tried.
    unprintedMessages.forEach (message) -> up.puts('up.render()', message)

    return opts.noneApplicable?()
