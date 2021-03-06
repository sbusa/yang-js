#
# Yang - bold outward facing expression and interactive manifestation
#
# represents a YANG schema expression (with nested children)

# external dependencies
parser = require 'yang-parser'
indent = require 'indent-string'

# local dependencies
Expression = require './expression'

class Yang extends Expression
  ###
  # The `constructor` performs recursive parsing of passed in
  # statement and sub-statements.
  #
  # It performs semantic and contextual validations on the provided
  # schema and returns the final JS object tree structure.
  #
  # Accepts: string or JS Object
  # Returns: this
  ###
  constructor: (schema, parent) ->
    switch
      when schema instanceof Yang
        super schema.kind, schema.tag, schema
        @extends schema.expressions.map (x) -> x.clone()
        return

      when schema instanceof Expression
        parent ?= schema.parent
        schema =
          kw:  schema.kind
          arg: schema.tag
          substmts: schema.expressions
      
      when typeof schema is 'string'
        try
          schema = (parser.parse schema) if typeof schema is 'string'
        catch e
          e.offset = 30 unless e.offset > 30
          offender = schema.slice e.offset-30, e.offset+30
          offender = offender.replace /\s\s+/g, ' '
          throw @error "invalid YANG syntax detected", offender

    unless typeof schema is 'object'
      throw @error "must pass in proper YANG schema"

    keyword = ([ schema.prf, schema.kw ].filter (e) -> e? and !!e).join ':'
    argument = schema.arg if !!schema.arg

    ext = parent?.lookup 'extension', keyword
    unless (ext instanceof Expression)
      throw @error "encountered unknown extension '#{keyword}'", schema
      
    if argument? and not ext.argument?
      throw @error "cannot contain argument for extension '#{keyword}'", schema
    if ext.argument? and not argument?
      throw @error "must contain argument '#{ext.argument}' for extension '#{keyword}'", schema
      
    origin = if ext instanceof Yang then ext.origin else ext
    super keyword, argument,
      parent:    parent
      root:      parent not instanceof Yang
      data:      origin?.data
      scope:     origin?.scope
      resolve:   origin?.resolve
      construct: origin?.construct
      predicate: origin?.predicate
      represent: ext.argument?.tag ? ext.argument

    @extends schema.substmts...
    
    @debug? "resolving #{keyword} Yang Expression..."
    @resolve()
    
    # perform final scoped constraint validation
    for kind, constraint of @scope when constraint in [ '1', '1..n' ]
      unless @hasOwnProperty kind
        throw @error "constraint violation for required '#{kind}' = #{constraint}"

    Object.defineProperties this,
      '_created': value: true
    if @parent instanceof Yang and @parent._created isnt true
      @parent.once 'created', => @emit 'created', this
    else @emit 'created', this

  clone: -> new Yang this

  # override private 'extend' prototype to always convert to Yang
  extend: (expr) -> super switch
    when expr instanceof Yang then expr
    else new Yang expr, this

  locate: (ypath) ->
    # TODO: figure out how to eliminate duplicate code-block section
    # shared with Expression
    return unless typeof ypath is 'string' and !!ypath
    ypath = ypath.replace /\s/g, ''
    if (/^\//.test ypath) and not @root
      return @parent.locate ypath
    [ key, rest... ] = ypath.split('/').filter (e) -> !!e
    return this unless key?

    if key is '..'
      return unless not @root
      return @parent.locate rest.join('/')
      
    match = key.match /^([\._-\w]+):([\._-\w]+)$/
    return super unless match?

    @debug? "looking for '#{match[1]}:#{match[2]}'"

    rest = rest.map (x) -> x.replace "#{match[1]}:", ''
    skey = [match[2]].concat(rest).join '/'

    # if (@lookup 'module', match[1]) or (@lookup 'prefix', match[1])
    if (@tag is match[1]) or (@lookup 'prefix', match[1])
      @debug? "(local) locate '#{skey}'"
      return super skey

    for m in @import ? [] when m.prefix.tag is match[1]
      @debug? "(external) locate #{skey}"
      return m.module.locate skey

    return undefined
      
  # Yang Expression can support 'tag' with prefix to another module
  # (or itself).
  lookup: (kind, tag) ->
    return super unless kind? and tag? and typeof tag is 'string'
    [ prefix..., arg ] = tag.split ':'
    return super unless prefix.length

    prefix = prefix[0]
    # check if current module's prefix
    ctx = @lookup 'prefix'
    return ctx.lookup kind, arg if ctx?.tag is prefix

    # check if submodule's parent prefix
    ctx = @lookup 'belongs-to'
    return ctx.module.lookup kind, arg if ctx?.prefix.tag is prefix

    # check if one of current module's imports
    imports = (@lookup 'import') ? []
    for m in imports when m.prefix.tag is prefix
      return m.module.lookup kind, arg

  # converts back to YANG schema string
  toString: (opts={}) ->
    opts.space ?= 2 # default 2 spaces
    s = @kind
    if @represent?
      s += ' ' + switch @represent
        when 'value' then "'#{@tag}'"
        when 'text' 
          "\n" + (indent '"'+@tag+'"', ' ', opts.space)
        else @tag
    sub =
      @expressions
        .filter (x) => x.parent is this
        .map (x) -> x.toString opts
        .join "\n"
    if !!sub
      s += " {\n" + (indent sub, ' ', opts.space) + "\n}"
    else
      s += ';'
    return s

module.exports = Yang
