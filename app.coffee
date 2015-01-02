html2text   = require 'html-to-text'
request     = require 'request'
marked      = require 'marked'
async       = require 'async'
less        = require 'less-middleware'
hljs        = require 'highlight.js'
http        = require 'http'
path        = require 'path'
Poet        = require 'poet'

# express stuff
express     = require 'express'
favicon     = require 'serve-favicon'
morgan      = require 'morgan'

{Renderer}  = marked

String::startsWith    ?= (str) -> 0 is @indexOf str
String::startsWithAny  = (lst) -> return true for str in lst when @startsWith str; false

app = express()
app.set 'port',         process.env.PORT or 3002
app.set 'views',        __dirname + '/views'
app.set 'view engine',  'jade'

app.set 'github name',            'chester1000'
app.set 'github repo url',        'https://api.github.com/repos/%s'
app.set 'github readme url',      'https://raw.github.com/%s/master/README.md'

app.set 'youtube embed url',      '<iframe width="853" height="480" src="//www.youtube.com/embed/%s" frameborder="0" allowfullscreen></iframe>'
app.set 'youtube url regex',      /^(?:http(?:s)?:\/\/)?(?:www\.)?(?:youtu\.be\/|youtube\.com\/(?:(?:watch)?\?(?:.*&)?v(?:i)?=|(?:embed|v|vi|user)\/))([^\?&\"'>]+)/
app.set 'youtube url regex old',  /^.*(?:youtu.be\/|v\/|e\/|u\/\w+\/|embed\/|v=)([^#\&\?]*).*/

app.use morgan 'dev'

app.use (req, res, next) ->
  if req.path.startsWithAny ['/post', '/stylesheets', '/bootstrap', '/images', '/github', '/javascripts']
    res.header 'Cache-Control', 'max-age=300'
  next()

app.use (req, res, next) ->
  unless req.is 'text/*' then next()
  else
    req.text = ''
    req.setEncoding 'utf8'
    req.on 'data', (chunk) -> req.text += chunk
    req.on 'end', next

# less middleware
app.use less __dirname,
  dest: path.join __dirname, 'public'
  force: true # WARN: only for debug
  preprocess: path: (p) -> p.replace /stylesheets/, 'less'
  postprocess: css: (css) -> '/* DO NOT EDIT THIS FILE. Look for `/less` directory instead! */\n' + css

app.use favicon path.join process.cwd(), 'public/favicon.ico'
app.use express.static path.join(__dirname, 'public'), maxAge: 300

app.get '/post-content/*', (req, res) ->
  res.header 'Cache-Control', 'max-age=300'
  res.sendfile path.join __dirname, '_posts', req.params[0]


attachGithubRepo = (repoName) ->
  fullRepoName = app.get('github name') + '/' + repoName
  getGithub = (type, callback) ->
    request
      headers: 'User-Agent': 'node.js'
      url: app.get('github ' + type + ' url').replace /%s/g, fullRepoName
    , callback

  camelCaseName = repoName.replace(/-/g, '')
  localPath = '/' + camelCaseName

  app.get localPath, (req, res) ->
    res.header 'Cache-Control', 'max-age=300'

    async.parallel [
      (cb) -> getGithub 'repo',   (err, resp, body) -> cb null, JSON.parse body
      (cb) -> getGithub 'readme', (err, resp, body) -> marked body, cb

    ], (err, results) ->
      return res.send err if err?

      info = results[0]
      res.render 'github',
        name: fullRepoName
        markdown: results[1]
        project:
          owner: info.owner
          title: info.name
          description: info.description

  path: localPath
  name: camelCaseName.replace /([a-z])([A-Z])/g, '$1 $2'

app.locals.repos = [
  attachGithubRepo 'Pretty-Binary-Clock'
  attachGithubRepo 'BitcoinMonitor'
  attachGithubRepo 'Tabs-Butcher'
  attachGithubRepo 'Weather-Happy'
  attachGithubRepo 'Dvorak-Programmer'
  attachGithubRepo 'Chrome-Bitcoin-Monitor'
]

# prefix relative picture urls and support youtube links
renderer = new Renderer()
renderer.image = (href, title, text) ->

  yt = href.match app.set 'youtube url regex'

  '<center class="resource">' + (

    if yt?
      '<div class="videoWrapper">' + (
        app.get('youtube embed url').replace '%s', yt[1]

      ) + '</div>'

    else
      href = '/post-content/' + href unless href.startsWithAny [ 'http', '/images' ]
      new Renderer().image href, title, text

  ) + '</center>'


marked.setOptions
  renderer: renderer
  gfm: true
  sanitize: true
  smartypants: true
  highlightClass: 'hljs'
  highlight: (code, lang) ->
    if lang?
      hljs.highlight(lang, code).value
    else
      hljs.highlightAuto(code).value


poet = Poet app,
  posts: './_posts'
  postsPerPage: 3

# using my own marked instead of one bundled with poet, because
# standard doesn't support easy class injection to a <pre> element.
.addTemplate
  ext: ['markdown', 'md']
  fn: (options) ->
    marked options.source

.addRoute '/', (req, res) ->
  res.render 'page',
    posts: poet.helpers.getPosts 0, 3
    page: 1

poet.init ->
  app.get '/rss', (req, res) ->
    posts = poet.helpers.getPosts 0, 5

    posts.forEach (post) ->
      post.rssDescription = html2text.fromString post.preview

    res.render 'rss', posts: posts

# random comment.
app.listen app.get('port'), ->
  console.log 'Express server listening on port ' + app.get 'port'

