u = up.util

class up.UrlPattern

  constructor: (pattern, @normalizeUrl = u.identity) ->
    @groupNames = []

    pattern = pattern.split(' ').map(@normalizeUrl).map(u.escapeRegExp).join('|')
    pattern = pattern.replace /\\\*/g, '.*?'
    pattern = pattern.replace /\:([\w-]+)/ig, (match, name) =>
      @groupNames.push(name)
      return '([^/?#]+)'
    @regexp = new RegExp('^' + pattern + '$')

  matches: (url) ->
    url = @normalizeUrl(url)
    return @regexp.test(url)

  recognize: (url) ->
    url = @normalizeUrl(url)
    if match = @regexp.exec(url)
      resolution = {}
      @groupNames.forEach (groupName, groupIndex) =>
        if value = match[groupIndex + 1]
          resolution[groupName] = value
      return resolution
