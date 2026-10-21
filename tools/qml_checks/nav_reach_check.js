// 列出 pages/*.qml 各自被谁 navigateTo(...), 找出"画了但进不去/根本没人调用"的页面
const fs = require('fs')
const path = require('path')
const root = process.argv[2] || path.resolve(__dirname, '../../qml')
const hits = {}

function walk(d) {
    for (const f of fs.readdirSync(d)) {
        const p = path.join(d, f)
        const st = fs.statSync(p)
        if (st.isDirectory()) { walk(p); continue }
        if (!f.endsWith('.qml')) continue
        const t = fs.readFileSync(p, 'utf8')
        const re = /navigateTo\(\s*['"](\w+)['"]/g
        let m
        while ((m = re.exec(t))) {
            const key = m[1]
            ;(hits[key] = hits[key] || new Set()).add(path.relative(root, p).replace(/\\/g, '/'))
        }
        const re2 = /case\s+['"]\w+['"]\s*:\s*\w+\.navBus\.navigateTo\(\s*['"](\w+)['"]/g
        while ((m = re2.exec(t))) {
            ;(hits[m[1]] = hits[m[1]] || new Set()).add(path.relative(root, p).replace(/\\/g, '/') + ' [drawer]')
        }
        const re3 = /page:\s*['"](\w+)['"]/g
        while ((m = re3.exec(t))) {
            ;(hits[m[1]] = hits[m[1]] || new Set()).add(path.relative(root, p).replace(/\\/g, '/') + ' [model]')
        }
    }
}
walk(root)

const pages = fs.readdirSync(path.join(root, 'pages')).filter(f => f.endsWith('.qml')).map(f => f.slice(0, -4))
for (const p of pages) {
    const h = hits[p]
    console.log((h ? [...h].sort().join(' | ') : '(无人调用)').padEnd(70) + ' <= ' + p)
}
console.log('--- pages 总数: ' + pages.length)
