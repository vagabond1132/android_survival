// Final 1 insect to reach 30
const fs = require('fs');
const path = 'assets/data/field_guide_insects.json';
const d = JSON.parse(fs.readFileSync(path, 'utf-8'));

d.insects.push({
  id: 'insect_chigger', cn: '恙螨', sci: 'Trombiculidae', cat: 'mite', lv: 2,
  alias: ['恙虫'], features: ['体长 0.2-0.5mm', '橙红色', '肉眼可见', '幼虫寄生'],
  kingdom: 'insecta', distribution: ['山东', '河南', '河北', '山西'],
  min_elevation: 0, max_elevation: 1500,
  habitats: ['草地', '灌丛', '田边'],
  active_months: ['5', '6', '7', '8', '9', '10'],
  venom_type: 'mite_saliva', venom_location: '口器',
  attack_distance_cm: 0, active_time: '全天',
  hibernation_months: ['11', '12', '1', '2', '3', '4'],
  symptoms: ['叮咬后焦痂', '恙虫病(立克次氏体)'],
  look_alike: [], first_aid_id: '',
  first_aid_links: { '叮咬': 'firstaid_mite_bite' },
  protective_gear: ['防螨', '扎紧裤口'],
  route_associations: [],
  representative_color: { h: 20, s: 80, v: 80 },
  images: ['whole'],
  description: '恙虫病媒介,北方夏季草地多。',
  source: '中国媒介生物学',
  reviewer: 'XX(昆虫学)'
});

fs.writeFileSync(path, JSON.stringify(d, null, 2));
console.log('昆虫总数:', d.insects.length);
