#!/usr/bin/env node
/**
 * @file doc_check.js
 * @brief 文档同步自检脚本
 *
 * 扫描 src/ 与 qml/ 改动,根据关键词推断需同步哪些文档。
 * 用法: node doc/06-工程规范/scripts/doc_check.js [since_commit]
 *   since_commit: 可选,只检查自该 commit 后的改动(需在 git 仓库)
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const APP_ROOT = path.resolve(__dirname, '../../..');
const SINCE = process.argv[2] || 'HEAD~1';

// 关键词 → 需要更新的文档
const RULES = [
    // === 严重:核心架构变更 ===
    {
        files: ['src/core/App.cpp', 'src/core/App.h'],
        keywords: ['m_\\w+\\.reset\\(\\)', 'm_\\w+\\.make_unique'],
        hint: 'App 初始化/服务生命周期变更',
        docs: [
            'doc/12-需求清单/需求清单与实现状态.md (服务列表与统计)',
            'doc/08-索引与概念/全代码索引.md (服务表)',
        ],
    },
    {
        files: ['src/core/Database.cpp', 'src/core/Database.h'],
        keywords: ['CREATE TABLE', 'migrate\\(\\)', 'createSchema'],
        hint: '数据库表结构变更',
        docs: [
            'doc/04-数据库/数据库设计文档.md',
            'doc/12-需求清单/需求清单与实现状态.md (持久化相关需求)',
            'doc/代码审查与测试报告.md (修复记录)',
        ],
    },
    {
        files: ['src/core/Config.cpp', 'src/core/Config.h'],
        keywords: ['setDefaults', 'defaultValue'],
        hint: 'Config 默认值变更',
        docs: [
            'doc/06-工程规范/工程规范手册.md (Config 用法)',
        ],
    },
    {
        files: ['src/core/Logger.cpp', 'src/core/Logger.h'],
        keywords: ['rotate', 'enforceTotalSize', 'maxFileSize', 'maxTotalSize'],
        hint: 'Logger 滚动/清理逻辑变更',
        docs: [
            'doc/06-工程规范/工程规范手册.md (日志规范)',
            'doc/12-需求清单/需求清单与实现状态.md (系统功能)',
        ],
    },
    {
        files: ['src/main.cpp'],
        keywords: ['QLocalServer', 'QLocalSocket', 'listen\\('],
        hint: '主入口/单实例锁/启动逻辑变更',
        docs: [
            'doc/12-需求清单/需求清单与实现状态.md',
            'doc/06-工程规范/工程规范手册.md',
        ],
    },
    // === 数据/资源变更 ===
    {
        files: ['assets/data/*.json'],
        keywords: [],  // 文件名级匹配
        hint: '数据文件变更',
        docs: [
            'doc/12-需求清单/需求清单与实现状态.md (第 9 节 数据维度)',
            'doc/00-文档总览.md (项目状态)',
        ],
    },
    // === QML 页面变更 ===
    {
        files: ['qml/pages/*.qml'],
        keywords: [],
        hint: 'QML 页面变更',
        docs: [
            'doc/12-需求清单/需求清单与实现状态.md (第 11 节 UI 页面)',
            'doc/08-索引与概念/全代码索引.md (QML 页面索引)',
        ],
    },
    // === 服务层变更 ===
    {
        files: ['src/routes/RouteService.cpp', 'src/routes/RouteService.h'],
        keywords: ['m_provinceIndex', 'm_monthIndex', 'rebuildIndex'],
        hint: 'RouteService 索引/性能优化',
        docs: [
            'doc/12-需求清单/需求清单与实现状态.md (第 5 节 路线)',
            'doc/代码审查与测试报告.md (修复/优化记录)',
        ],
    },
    {
        files: ['src/travel/TravelService.cpp', 'src/travel/TravelService.h'],
        keywords: [],
        hint: 'TravelService 变更',
        docs: [
            'doc/12-需求清单/需求清单与实现状态.md (第 8 节 自驾游)',
            'doc/08-索引与概念/全代码索引.md (TravelService)',
        ],
    },
    {
        files: ['src/equipment/EquipmentService.cpp', 'src/equipment/EquipmentService.h'],
        keywords: [],
        hint: 'EquipmentService 变更 (2026-09-21 阶段 I-3 改名 EquipmentEngine → EquipmentService)',
        docs: [
            'doc/12-需求清单/需求清单与实现状态.md (第 7 节 智能装备)',
        ],
    },
    {
        files: ['src/firstaid/FirstAidService.cpp', 'src/firstaid/EmergencyService.cpp'],
        keywords: [],
        hint: '急救/紧急服务变更',
        docs: [
            'doc/12-需求清单/需求清单与实现状态.md (第 1 节 救命核心)',
        ],
    },
    {
        files: ['src/species/SpeciesService.cpp', 'src/species/PlantService.cpp', 'src/species/AnimalService.cpp', 'src/species/InsectService.cpp', 'src/species/MushroomService.cpp'],
        keywords: [],
        hint: '物种服务变更',
        docs: [
            'doc/12-需求清单/需求清单与实现状态.md (第 1 节 救命核心)',
            'doc/00-文档总览.md (物种条数)',
        ],
    },
    {
        files: ['src/map/MapService.cpp', 'src/map/MapService.h'],
        keywords: [],
        hint: '地图服务变更',
        docs: [
            'doc/12-需求清单/需求清单与实现状态.md (第 3 节 地图与轨迹)',
        ],
    },
    {
        files: ['src/recognition/RecognitionEngine.cpp', 'src/recognition/CloudRecognitionService.cpp'],
        keywords: [],
        hint: '识别引擎变更',
        docs: [
            'doc/12-需求清单/需求清单与实现状态.md (第 2 节 拍照识别)',
            'doc/代码审查与测试报告.md (F2 状态)',
        ],
    },
    {
        files: ['src/platform/AndroidPlatform.cpp', 'src/platform/PermissionManager.cpp'],
        keywords: [],
        hint: '平台/权限变更',
        docs: [
            'doc/12-需求清单/需求清单与实现状态.md (第 9 节 系统功能)',
            'doc/06-工程规范/工程规范手册.md (平台规范)',
        ],
    },
    // === 构建/部署 ===
    {
        files: ['CMakeLists.txt'],
        keywords: ['add_executable', 'qt_add_executable', 'qt_add_library', 'find_package'],
        hint: 'CMake 构建配置变更',
        docs: [
            'doc/08-索引与概念/全代码索引.md (文件统计)',
            'doc/07-部署与发布/Docker构建APK手册.md (构建步骤)',
        ],
    },
    {
        files: ['Dockerfile.android', 'docker-compose.yml'],
        keywords: [],
        hint: 'Docker 镜像/Compose 变更',
        docs: [
            'doc/07-部署与发布/Docker构建APK手册.md (镜像构建步骤)',
        ],
    },
    {
        files: ['build_apk.sh', 'build_apk.bat'],
        keywords: [],
        hint: '打包脚本变更',
        docs: [
            'doc/07-部署与发布/Docker构建APK手册.md (构建命令)',
        ],
    },
    // === 测试 ===
    {
        files: ['tests/unit/*.cpp'],
        keywords: ['QTEST_MAIN'],
        hint: '新增/修改单元测试',
        docs: [
            'doc/代码审查与测试报告.md (测试覆盖)',
        ],
    },
];

function run(cmd) {
    try {
        return execSync(cmd, { encoding: 'utf-8', cwd: APP_ROOT }).trim();
    } catch (e) {
        return '';
    }
}

function getChangedFiles() {
    // 优先用 git diff
    if (fs.existsSync(path.join(APP_ROOT, '.git'))) {
        const out = run(`git diff --name-only ${SINCE}`);
        if (out) return out.split('\n').filter(f => f.trim());
    }
    // 退化:扫描 src qml assets CMakeLists.txt Dockerfile docker-compose.yml build_apk.sh tests
    // 对 Windows 用 find 不稳定,改用 Node 递归扫描
    const out = [];
    const scanDirs = ['src', 'qml', 'assets', 'tests'];
    const scanFiles = ['CMakeLists.txt', 'Dockerfile.android', 'docker-compose.yml', 'build_apk.sh', 'build_apk.bat'];
    for (const d of scanDirs) {
        const full = path.join(APP_ROOT, d);
        if (fs.existsSync(full)) walk(full, out);
    }
    for (const f of scanFiles) {
        const full = path.join(APP_ROOT, f);
        if (fs.existsSync(full)) out.push(f);
    }
    return out;
}

function walk(dir, out, exts = ['.cpp', '.h', '.qml', '.json', '.sh', '.bat']) {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const e of entries) {
        const full = path.join(dir, e.name);
        const rel = path.relative(APP_ROOT, full);
        if (e.isDirectory()) {
            walk(full, out, exts);
        } else if (exts.some(ext => e.name.endsWith(ext))) {
            out.push(rel.replace(/\\/g, '/'));
        }
    }
}

function matchRule(file, rule) {
    // 文件匹配(glob)
    if (rule.files.some(pattern => {
        if (pattern.includes('*')) {
            const regex = new RegExp('^' + pattern.replace(/\*/g, '.*') + '$');
            return regex.test(file);
        }
        return file === pattern || file.startsWith(pattern.replace(/\*$/, ''));
    })) {
        if (rule.keywords.length === 0) return true;
        try {
            const content = fs.readFileSync(path.join(APP_ROOT, file), 'utf-8');
            return rule.keywords.some(kw => new RegExp(kw).test(content));
        } catch (e) {
            return false;
        }
    }
    return false;
}

function main() {
    const files = getChangedFiles();
    if (files.length === 0) {
        console.log('[doc_check] 没有检测到改动');
        return;
    }

    console.log(`[doc_check] 扫到 ${files.length} 个改动文件:`);
    files.forEach(f => console.log('  - ' + f));
    console.log('');

    const triggeredDocs = new Map();  // doc -> hints
    for (const file of files) {
        for (const rule of RULES) {
            if (matchRule(file, rule)) {
                for (const doc of rule.docs) {
                    if (!triggeredDocs.has(doc)) {
                        triggeredDocs.set(doc, new Set());
                    }
                    triggeredDocs.get(doc).add(`${file} (${rule.hint})`);
                }
            }
        }
    }

    if (triggeredDocs.size === 0) {
        console.log('[doc_check] 无需同步文档(改动未触发任何规则)');
        return;
    }

    console.log('='.repeat(70));
    console.log('[doc_check] 需同步的文档:');
    console.log('='.repeat(70));
    for (const [doc, hints] of triggeredDocs) {
        console.log(`\n📄 ${doc}`);
        for (const h of hints) {
            console.log(`   - ${h}`);
        }
    }
    console.log('\n' + '='.repeat(70));
    console.log(`共 ${triggeredDocs.size} 个文档需要同步检查`);
    console.log('='.repeat(70));
}

main();
