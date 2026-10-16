/**
 * @file routes_add_camel.js
 * @brief 给 routes.json 4 个重复字段加 camelCase 别名
 *
 * 2026-09-11 (#66):
 *   routes.json snake_case 与 QML 端 camelCase 混用:
 *     is_wild  / isWild
 *     has_permit / hasPermit
 *     route_nature / routeNature
 *     not_recommended / notRecommended
 *     not_recommended_reason / notRecommendedReason
 *   QML 端用 camelCase, 但 RouteService 读 snake_case 优先, 写时输出 camelCase.
 *   跑本脚本后 routes.json 同时含两套, 未来去掉 snake_case 字段时不需要再改 RouteService.
 *
 * 跑法: node scripts/routes_add_camel.js
 */
const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, '..', 'assets', 'data', 'routes.json');
const data = JSON.parse(fs.readFileSync(file, 'utf-8'));

const SNAKE_TO_CAMEL = {
    'is_wild': 'isWild',
    'has_permit': 'hasPermit',
    'route_nature': 'routeNature',
    'not_recommended': 'notRecommended',
    'not_recommended_reason': 'notRecommendedReason'
};

let added = 0;
for (const r of data.routes) {
    for (const [snake, camel] of Object.entries(SNAKE_TO_CAMEL)) {
        if (snake in r && !(camel in r)) {
            r[camel] = r[snake];
            added++;
        }
    }
}

fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n', 'utf-8');
console.log(`Added ${added} camelCase aliases to ${data.routes.length} routes`);
console.log(`File: ${file}`);
