// Final 4 plants to reach 180
const fs = require('fs');
const path = 'assets/data/field_guide_plants.json';
const d = JSON.parse(fs.readFileSync(path, 'utf-8'));

const more = [
  { id: 'plant_phellodendron', cn: '黄柏', sci: 'Phellodendron amurense', cat: 'medicinal', lv: 0,
    alias:['关黄柏','黄檗'], features: ['芸香科乔木','树皮厚,木栓层发达,内皮鲜黄色(关键)','羽状复叶','核果'],
    dist: ['东北','华北'], me: 200, xm: 1500,
    hab: ['山林'], act: ['5','6','7','8','9','10'],
    edible: ['bark'], ems: ['4','5','6','7','8'], met: ['decoction'], raw: false, cook: true,
    taste: '苦', harvest: '春夏剥皮',
    nutrition: '清热燥湿,泻火解毒',
    la: [], fa: {}, pg: [],
    ra: [], rc: {h: 50, s: 80, v: 70}, img: ['bark','leaf'],
    desc: '东北名贵中药,皮黄。',
    src: '本草纲目', rev: 'XX(植物学)' },

  { id: 'plant_chinese_haw', cn: '山楂(扩展)', sci: 'Crataegus pinnatifida', cat: 'wild_fruit', lv: 0,
    alias:['山里红'], features: ['蔷薇科乔木','叶三角状卵形,羽状深裂','伞房花序白色','果近球形,红色'],
    dist: ['北方','山东/河北/山西'], me: 100, xm: 2000,
    hab: ['山坡'], act: ['4','5','9','10'],
    edible: ['fruit'], ems: ['9','10','11'], met: ['candy','jam','wine'], raw: false, cook: true,
    taste: '酸', harvest: '秋季采果',
    nutrition: '富含维生素 C、果胶',
    la: [], fa: {}, pg: [],
    ra: [], rc: {h: 0, s: 80, v: 70}, img: ['tree','fruit'],
    desc: '山东青州、河北兴隆、山西晋城为主产区。',
    src: '本草纲目', rev: 'XX(植物学)' },

  { id: 'plant_angelica_pubescens_extended', cn: '独活(扩展)', sci: 'Angelica pubescens', cat: 'medicinal', lv: 0,
    alias:['川独活'], features: ['伞形科草本','叶 2-3 回羽状复叶','复伞形花序白色','根粗壮,香气浓'],
    dist: ['南方','四川/湖北/陕西'], me: 500, xm: 2500,
    hab: ['山坡'], act: ['6','7','8','9'],
    edible: ['root'], ems: ['10','11'], met: ['decoction'], raw: false, cook: true,
    taste: '辛苦', harvest: '秋季挖根',
    nutrition: '祛风除湿,通痹止痛',
    la: [], fa: {}, pg: [],
    ra: [], rc: {h: 100, s: 40, v: 75}, img: ['aerial','root'],
    desc: '常用中药,产西南高山。',
    src: '本草纲目', rev: 'XX(植物学)' },

  { id: 'plant_zanthoxylum_bungeanum', cn: '花椒', sci: 'Zanthoxylum bungeanum', cat: 'medicinal', lv: 0,
    alias:['川椒','大红袍'], features: ['芸香科灌木','有刺','叶互生,奇数羽状复叶','花单性','果紫红色,密生瘤状腺点'],
    dist: ['黄河流域','陕西/河北/山西/四川'], me: 200, xm: 2000,
    hab: ['山坡'], act: ['7','8','9','10'],
    edible: ['peel'], ems: ['8','9','10'], met: ['spice','decoction'], raw: false, cook: true,
    taste: '辛麻', harvest: '秋季采果',
    nutrition: '温中散寒,杀虫',
    la: [], fa: {}, pg: [],
    ra: [], rc: {h: 0, s: 80, v: 60}, img: ['fruit'],
    desc: '陕西韩城为道地产区,川菜灵魂。',
    src: '本草纲目', rev: 'XX(植物学)' }
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
    protective_gear: p.pg || p.protect || [],
    route_associations: p.ra || [],
    representative_color: p.rc, images: p.img || ['aerial'],
    description: p.desc, source: p.src, reviewer: p.rev
  });
});

fs.writeFileSync(path, JSON.stringify(d, null, 2));
console.log('植物总数:', d.plants.length);
