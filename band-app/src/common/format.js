// Small helpers shared by the pages.
function two(n) {
  return (n < 10 ? '0' : '') + n
}

module.exports = {
  two: two,
  clock: function (d) {
    return two(d.getHours()) + ':' + two(d.getMinutes())
  },
  num: function (v) {
    if (v === null || v === undefined) return '--'
    var s = String(Math.round(v))
    var out = ''
    while (s.length > 3) {
      out = ',' + s.slice(-3) + out
      s = s.slice(0, -3)
    }
    return s + out
  },
  hm: function (minutes) {
    if (minutes === null || minutes === undefined) return '--'
    return Math.floor(minutes / 60) + 'h ' + (minutes % 60) + 'm'
  },
  pct: function (v, goal) {
    if (!v || !goal) return 0
    return Math.min(100, Math.round((v * 100) / goal))
  },
  ago: function (seconds) {
    var now = Math.floor(Date.now() / 1000)
    var d = Math.max(0, now - seconds)
    if (d < 60) return 'now'
    if (d < 3600) return Math.floor(d / 60) + 'm'
    if (d < 86400) return Math.floor(d / 3600) + 'h'
    return Math.floor(d / 86400) + 'd'
  },
  mmss: function (s) {
    return two(Math.floor(s / 60)) + ':' + two(s % 60)
  }
}
