### yang-js
#
# The **yang-js** module provides support for basic set of YANG schema
# modeling language by using the built-in *extension* syntax to define
# additional schema language constructs.
#
###
console.debug ?= console.log if process.env.yang_debug?

fs   = require 'fs'
path = require 'path'

Yang       = require './yang'
Bundle     = require './bundle'
Expression = require './expression'

# private singleton instance of the "yang-v1-spec" Expressions
Origin =
  new Expression 'origin', 'yang-lang-spec',
    scope:
      extension: '0..n'
      typedef:   '0..n'
  .extends (require './yang-lang-extensions')...
  .extends (require './yang-lang-typedefs')...

# private singleton instance of the "yang-v1-lang" YANG module (using Origin)
Source = new Yang (fs.readFileSync (path.resolve __dirname, '../yang-language.yang'), 'utf-8'), Origin

# private singleton registry for stateful schema dependency processing (using Source)
Registry = new Bundle 'yang-library',
  parent: Source
  scope:
    module: '0..n'

# primary method for the 'yang-js' module for creating schema driven Yang Expressions
yang = (schema, parent=Registry) -> new Yang schema, parent

#
# declare exports
#
exports = module.exports = (schema) -> (-> @eval arguments...).bind (yang schema)

# parses YANG schema text input into Yang Expression
#
# accepts: YANG schema text
# returns: Yang Expression
exports.parse = (schema) -> (yang schema)

# composes arbitrary JS object into Yang Expression
#
# accepts: JS object
# returns: Yang Expression
exports.compose = (name, data, opts={}) ->
  source = opts.source ? Source
  # explict compose
  if opts.kind?
    ext = source.lookup 'extension', opts.kind
    unless ext instanceof Expression
      throw new Error "unable to find requested '#{opts.kind}' extension"
    return new Yang (ext.compose data, key: name), source
  
  # implicit compose (dynamic discovery)
  for ext in source.extension when ext.compose instanceof Function
    console.debug? "checking data if #{ext.tag}"
    try return new Yang (ext.compose data, key: name), source

exports.bundle = (schema...) ->

exports.resolve = (from..., name) ->
  return null unless typeof name is 'string'
  dir = from = switch
    when from.length then from[0]
    else path.resolve()
  while not found? and dir not in [ '/', '.' ]
    console.debug? "resolving #{name} in #{dir}/package.json"
    try
      found = require("#{dir}/package.json").models[name]
      dir   = path.dirname require.resolve("#{dir}/package.json")
    dir = path.dirname dir unless found?
  file = switch
    when found? and /^[\.\/]/.test found then path.resolve dir, found
    when found? then @resolve found, name
  file ?= path.resolve from, "#{name}.yang"
  console.debug? "checking if #{file} exists"
  return if fs.existsSync file then file else null
      
# convenience to add a new YANG module into the Registry by filename
exports.require = (name, opts={}) ->
  opts.basedir ?= ''
  opts.resolve ?= true
  extname  = path.extname name
  filename = path.resolve opts.basedir, name
  basedir  = path.dirname filename
  
  try model = switch extname
    when '.yang' then yang (fs.readFileSync filename, 'utf-8')
    when ''      then require (@resolve name)
    else require filename
  catch e
    console.debug? e
    throw e unless opts.resolve and e.name is 'ExpressionError' and e.context.kind is 'import'

    # try to find the dependency module for import
    dependency = @resolve basedir, e.context.tag
    unless dependency?
      e.message = "unable to auto-resolve '#{e.context.tag}' dependency module"
      throw e

    # update Registry with the dependency module
    Registry.update (@require dependency)
    
    # try the original request again
    model = @require arguments...
    
  return Registry.update model

# enable require to handle .yang extensions
exports.register = (opts={}) ->
  require.extensions?['.yang'] ?= (m, filename) ->
    m.exports = exports.require filename, opts
  return exports

# expose key class definitions
exports.Yang = Yang
exports.Registry  = Registry
exports.XPath = require './xpath'
