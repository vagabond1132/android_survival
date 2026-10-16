// Final 4 plants to reach 100
const fs = require('fs');
const path = 'assets/data/field_guide_plants.json';
const d = JSON.parse(fs.readFileSync(path, 'utf-8'));

const more = [
  { id: 'plant_christmasholly', cn: '构骨', sci: 'Ilex cornuta', cat: 'ornamental', lv: 0,
    alias:['猫儿刺', '老虎刺'], features: ['常绿灌木', '叶互生,革质,四角状长方形,边缘有刺齿', '花小黄绿色', '果红色'],
    dist: ['山东', '河南', '河北南部'], me: 0, xm: 1000,
    hab: ['庭院', '山坡'], act: ['4', '5', '11', '12'],
    edible: [], ems: [], met: [], raw: false, cook: false,
    taste: '', harvest: '',
    nutrition: '观赏',
    la: [], fa: {}, ra: [],
    rc: { h: 0, s: 80, v: 60 }, img: ['tree', 'fruit'],
    desc: '叶形奇特的观赏灌木,南方多。',
    src: '中国野菜图鉴', rev: 'XX(植物学)' },

  { id: 'plant_viburnum', cn: '荚蒾', sci: 'Viburnum dilatatum', cat: 'ornamental', lv: 0,
    alias:['鸡树条'], features: ['落叶灌木', '叶对生,宽倒卵形', '花小白色,复伞形花序', '果红色'],
    dist: ['山东', '山西', '河北', '河南'], me: 200, xm: 2000,
    hab: ['山坡', '林缘'], act: ['5', '6', '9', '10'],
    edible: [], ems: [], met: [], raw: false, cook: false,
    taste: '', harvest: '',
    nutrition: '观赏',
    la: [], fa: {}, ra: [],
    rc: { h: 0, s: 80, v: 70 }, img: ['tree', 'fruit'],
    desc: '北方常见观赏灌木。',
    src: '中国野菜图鉴', rev: 'XX(植物学)' },

  { id: 'plant_cotoneaster_horizontalis_2', cn: '灰栒子', sci: 'Cotoneaster acutifolius', cat: 'ornamental', lv: 0,
    alias:['黑果栒子'], features: ['落叶灌木', '叶互生,卵形', '花小,粉红色', '果黑色'],
    dist: ['山东', '山西', '河北', '河南', '内蒙古'], me: 200, xm: 2500,
    hab: ['山坡', '灌丛'], act: ['5', '6', '9', '10'],
    edible: [], ems: [], met: [], raw: false, cook: false,
    taste: '', harvest: '',
    nutrition: '观赏',
    la: [], fa: {}, ra: [],
    rc: { h: 280, s: 30, v: 40 }, img: ['tree', 'fruit'],
    desc: '北方常见观赏灌木。',
    src: '中国野菜图鉴', rev: 'XX(植物学)' },

  { id: 'plant_buddleja', cn: '醉鱼草', sci: 'Buddleja lindleyana', cat: 'poisonous', lv: 2,
    alias:['闹鱼花'], features: ['落叶灌木', '叶对生,披针形,叶背有绒毛', '花紫色,穗状花序', '蒴果'],
    dist: ['山东', '河南', '河北南部', '山西南部'], me: 100, xm: 1500,
    hab: ['山坡', '灌丛', '路旁'], act: ['5', '6', '7', '8'],
    symptoms: ['全株有小毒', '误食引起恶心呕吐、腹泻'],
    la: [], fa: { '误食': 'firstaid_plant_poisoning' },
    protect: ['不食不碰'],
    ra: [],
    rc: { h: 280, s: 60, v: 60 }, img: ['flower'],
    desc: '花艳丽但全株有毒。',
    src: '中国毒植物志', rev: 'XX(植物学)' }
];

more.forEach(p => {
  d.plants.push({
    id: p.id, common_name: p.cn, scientific_name: p.sci, kingdom: 'plantae',
    category: p.cat, danger_level: p.lv, alias: p.alias, features: p.features,
    distribution: p.dist, min_elevation: p.me, max_elevation: p.xm,
    habitats: p.hab, active_months: p.act,
    edible_part: p.edible || [], edible_months: p.ems || [],
    edible_method: p.met || [], raw_edible: p.raw || false, must_cook: p.cook || false,
    taste: p.taste || '', harvest_tips: p.harvest || '', nutrition: p.nutrition || '',
    symptoms: p.symptoms || [], look_alike: p.la || [],
    first_aid_id: '', first_aid_links: p.fa || {},
    protective_gear: p.protect || [],
    route_associations: p.ra || [],
    representative_color: p.rc, images: p.img || ['aerial'],
    description: p.desc, source: p.src, reviewer: p.rev
  });
});

fs.writeFileSync(path, JSON.stringify(d, null, 2));
console.log('植物总数:', d.plants.length);
