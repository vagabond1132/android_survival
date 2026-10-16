// Final 3 animals to reach 50
const fs = require('fs');
const path = 'assets/data/field_guide_animals.json';
const d = JSON.parse(fs.readFileSync(path, 'utf-8'));

const more = [
  { id: 'animal_rana_amurensis', cn: '东北林蛙', sci: 'Rana amurensis', cat: 'amphibian', lv: 0,
    alias:['哈士蟆'], features:['体长 4-6cm','背部有八字形斑','腹部白色带红点'],
    dist:['山东','河北','山西'], me: 200, xm: 1500,
    hab:['林下','溪流'], act:['4','5','6','7','8','9','10'],
    venom:'none', ven_loc:'', atk:0, time:'夜间', hib:['11','12','1','2','3'],
    protect:'省级保护', symptoms:[],
    la:[], fa:{}, pg:[],
    ra:[], rc:{h:30,s:40,v:50}, img:['whole'],
    desc:'北方常见蛙类。',
    src:'中国两栖爬行动物志', rev:'XX 教授(动物学)' },

  { id: 'animal_scolopendra', cn: '少棘蜈蚣', sci: 'Scolopendra subspinipes', cat: 'mammal_common', lv: 3,
    alias:['蜈蚣'], features:['体长 10-15cm','体扁','21 节','具毒颚'],
    dist:['山东','河南','河北','山西'], me: 0, xm: 1500,
    hab:['石缝','土块下','潮湿处'], act:['4','5','6','7','8','9','10'],
    venom:'arthropod', ven_loc:'毒颚', atk:0, time:'夜间', hib:['11','12','1','2','3'],
    protect:'无', symptoms:['咬伤剧痛红肿','过敏者可能发热'],
    la:[], fa:{'咬伤':'firstaid_centipede_bite'},
    pg:['翻动石块小心'],
    ra:[], rc:{h:30,s:30,v:30}, img:['whole'],
    desc:'北方常见。',
    src:'中国无脊椎动物志', rev:'XX 教授(动物学)' },

  { id: 'animal_scorpio', cn: '东亚钳蝎', sci: 'Mesobuthus martensii', cat: 'mammal_common', lv: 3,
    alias:['全蝎', '钳蝎'], features:['体长 5-8cm','头胸部短','后腹部 6 节','末端有尾刺'],
    dist:['山东','河南','河北','山西'], me: 0, xm: 1500,
    hab:['土墙缝','石块下'], act:['4','5','6','7','8','9','10'],
    venom:'scorpion', ven_loc:'尾刺', atk:0, time:'夜间', hib:['11','12','1','2','3'],
    protect:'无', symptoms:['蛰伤剧痛、麻木','严重者心律失常'],
    la:[], fa:{'蛰伤':'firstaid_scorpion_sting'},
    pg:['检查衣物鞋袜','夜间勿赤脚'],
    ra:[], rc:{h:30,s:30,v:30}, img:['whole'],
    desc:'北方山区可见,中药材(全蝎)。',
    src:'中国无脊椎动物志', rev:'XX 教授(动物学)' }
];

more.forEach(p => {
  d.animals.push({
    id: p.id, common_name: p.cn, scientific_name: p.sci, kingdom: 'animalia',
    category: p.cat, danger_level: p.lv, alias: p.alias, features: p.features,
    distribution: p.dist, min_elevation: p.me, max_elevation: p.xm,
    habitats: p.hab, active_months: p.act,
    venom_type: p.venom || 'none', venom_location: p.ven_loc || '',
    attack_distance_cm: p.atk || 0, active_time: p.time || '',
    hibernation_months: p.hib || [], protection_level: p.protect || '无',
    symptoms: p.symptoms || [], look_alike: p.la || [],
    first_aid_id: '', first_aid_links: p.fa || {},
    protective_gear: p.pg || [],
    route_associations: p.ra || [],
    representative_color: p.rc, images: p.img || ['whole'],
    description: p.desc, source: p.src, reviewer: p.rev
  });
});

fs.writeFileSync(path, JSON.stringify(d, null, 2));
console.log('动物总数:', d.animals.length);
