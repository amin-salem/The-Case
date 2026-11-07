"""Editorial transcription of the visually inspected contact sheets, not image inference."""
import json,hashlib
from pathlib import Path
R=Path(__file__).resolve().parents[1]
ages=json.load(open(R/'docs/portrait-ages.json'));ages.update(m_mid_researcher=46,m_mid_worker=36,f_mid_waitress=32)
# Explicit wardrobe observations; the occupational suffix alone is NOT a role restriction.
wardrobe={
'f_mid_agent':'charcoal jacket and black scarf','f_mid_archaeologist':'olive scarf and dark coat','f_mid_attorney':'dark burgundy scarf and dark jacket','f_mid_baker':'pink scarf and black blouse','f_mid_banker':'camel blazer and black scarf','f_mid_business':'black scarf and plain black top','f_mid_chef':'black work top and black scarf','f_mid_cleaner':'dark grey layered coat and black scarf','f_mid_clerk':'dark teal scarf and brown jacket','f_mid_commander':'dark formal uniform and black scarf','f_mid_curator':'cream scarf and dark jacket','f_mid_designer':'mauve scarf and dark blouse','f_mid_director':'black scarf and black coat','f_mid_doctor':'white medical coat and black scarf','f_mid_gallery':'mustard scarf and dark coat','f_mid_guest':'olive jacket and black scarf','f_mid_housewife':'patterned russet scarf and dark top','f_mid_inspector':'black scarf and dark coat','f_mid_journalist':'burgundy scarf and brown jacket','f_mid_judge':'dark formal robe and black scarf','f_mid_laborer':'yellow work jacket and black scarf','f_mid_lawyer':'black scarf and dark blazer','f_mid_librarian':'burgundy scarf and textured cardigan','f_mid_manager':'black scarf and dark top','f_mid_mechanic':'brown work jacket and blue-grey scarf','f_mid_officer':'dark uniform and black scarf','f_mid_pastry':'patterned scarf and light apron','f_mid_pharmacist':'cream white coat and black scarf','f_mid_pilot':'black uniform jacket white shirt and tie','f_mid_publisher':'dark tailored jacket and black scarf','f_mid_restorer':'dark coat scarf and goggles on head','f_mid_scholar':'tan scarf and dark jacket','f_mid_scientist':'white laboratory coat tan scarf and goggles on head','f_mid_singer':'patterned burgundy scarf and dark top','f_mid_soldier':'olive military shirt and green scarf','f_mid_surgeon':'blue surgical clothing and lowered mask','f_mid_teacher':'black scarf and dark top','f_mid_widow':'black scarf and black clothing','f_mid_witness':'green scarf and dark coat',
'f_old_aristocrat':'green scarf jewellery and dark top','f_old_baker':'patterned scarf and dark top','f_old_cook':'olive scarf and apron','f_old_countess':'black scarf and dark patterned jacket','f_old_fortune':'burgundy scarf and dark clothing','f_old_grandma':'black scarf and dark top','f_old_neighbor':'patterned brown scarf and brown cardigan','f_old_professor':'black scarf and dark jacket','f_old_retired':'mustard scarf and brown cardigan','f_old_retiree':'burgundy scarf and knitted cardigan','f_old_rich':'black scarf and formal dark clothing','f_old_seamstress':'rust scarf and brown clothing','f_old_shopkeeper':'black scarf and black top','f_old_socialite':'black scarf pearl necklace and dark jacket','f_old_villager':'patterned rust scarf and brown knitwear','f_old_widow':'cream scarf and dark coat',
'f_young_artist':'brown scarf and patterned top','f_young_athlete':'dark zipped sports jacket and black scarf','f_young_bookworm':'teal scarf and brown coat with bag strap','f_young_chemist':'white laboratory coat and light grey scarf','f_young_cook':'white kitchen uniform and dark scarf','f_young_firefighter':'reflective black yellow protective jacket','f_young_nurse':'white medical uniform and white head covering','f_young_painter':'paint-marked shirt and patterned scarf','f_young_photographer':'mustard scarf and dark coat with strap','f_young_receptionist':'black scarf and dark top','f_young_researcher':'white laboratory coat and dark scarf','f_young_student':'dark scarf and plain dark clothing','f_young_waitress':'black scarf and plain black top',
'm_mid_artist':'dark artistic work jacket; hand visible','m_mid_barista':'dark shirt and brown apron','m_mid_business':'grey formal jacket white shirt','m_mid_captain':'dark nautical jacket and peaked cap','m_mid_chef':'white chef coat','m_mid_conductor':'dark formal uniform and peaked cap','m_mid_cook':'white kitchen coat and brown apron','m_mid_doctor':'white medical coat and stethoscope','m_mid_driver':'brown rugged jacket','m_mid_fixer':'brown work shirt','m_mid_guard':'dark uniform and cap','m_mid_lawyer':'black suit white shirt and tie','m_mid_lecturer':'brown tweed jacket and white open collar','m_mid_merchant':'brown textured coat','m_mid_nurse':'blue medical scrubs','m_mid_officer':'dark suit white shirt and tie','m_mid_photographer':'brown jacket with shoulder strap','m_mid_policeman':'dark police uniform with epaulettes','m_mid_resident':'plain beige collared shirt','m_mid_roadworker':'yellow reflective work jacket','m_mid_sailor':'dark hooded heavy coat','m_mid_teacher':'plain olive shirt','m_mid_technician':'dark work clothes with cap and straps','m_mid_tycoon':'dark formal suit and tie',
'm_old_bakerman':'brown checked shirt and cardigan','m_old_boss':'dark formal jacket and black shirt','m_old_butler':'white shirt black waistcoat and bow tie','m_old_captain':'dark coat and flat cap','m_old_cleric':'white turban and brown religious robe','m_old_farmer':'brown jacket and flat cap','m_old_fisher':'brown coat and knitted cap','m_old_flatcap':'brown jacket and flat cap','m_old_gardener':'plain olive work shirt','m_old_grandpa':'beige cardigan and open collar','m_old_jurist':'dark formal jacket white shirt','m_old_painter':'brown jacket and scarf','m_old_physician':'dark jacket white collar and tie','m_old_professor':'dark textured jacket','m_old_rich':'black formal coat','m_old_schoolmaster':'brown formal jacket and tie','m_old_scientist':'white laboratory coat and tie','m_old_tailor':'brown waistcoat shirt and patterned scarf','m_old_warden':'brown uniform with shoulder insignia','m_old_woolcap':'brown coat and knitted cap',
'm_young_athlete':'dark sports jacket','m_young_boxer':'dark hooded sweatshirt','m_young_casual':'plain dark jacket','m_young_conscript':'olive military shirt','m_young_courier':'brown coat with shoulder strap','m_young_designer':'plain dark turtleneck','m_young_dj':'dark shirt and headphones','m_young_it':'plain dark shirt','m_young_student':'plain dark clothing','m_young_undergrad':'brown jacket with backpack straps','m_young_waiter':'white shirt black waistcoat and tie','m_young_worker':'plain blue work shirt',
'm_mid_researcher':'plain teal jacket and cream collarless shirt','m_mid_worker':'plain olive collared shirt','f_mid_waitress':'plain charcoal blouse and black scarf'}
uniforms={
'f_mid_commander':'military','f_mid_doctor':'medical','f_mid_judge':'judicial','f_mid_laborer':'construction','f_mid_officer':'security','f_mid_pastry':'catering','f_mid_pharmacist':'medical','f_mid_pilot':'aviation','f_mid_scientist':'laboratory','f_mid_soldier':'military','f_mid_surgeon':'medical','f_old_cook':'catering','f_young_chemist':'laboratory','f_young_cook':'catering','f_young_firefighter':'firefighting','f_young_nurse':'medical','f_young_researcher':'laboratory','m_mid_barista':'catering','m_mid_captain':'nautical','m_mid_chef':'catering','m_mid_conductor':'railway','m_mid_cook':'catering','m_mid_doctor':'medical','m_mid_guard':'security','m_mid_nurse':'medical','m_mid_policeman':'police','m_mid_roadworker':'construction','m_old_butler':'hospitality','m_old_cleric':'religious','m_old_scientist':'laboratory','m_old_warden':'security','m_young_conscript':'military','m_young_dj':'music','m_young_waiter':'hospitality','f_mid_restorer':'restoration'}
glasses=set('f_mid_attorney f_mid_librarian f_mid_publisher f_mid_scholar f_old_professor f_old_retired f_old_seamstress f_old_shopkeeper f_young_chemist f_young_student m_mid_doctor m_mid_lecturer m_mid_researcher m_old_jurist m_old_physician m_old_professor m_old_schoolmaster m_old_scientist m_old_tailor m_young_designer m_young_it m_young_student'.split())
# Male visual signatures: hair colour/style, facial hair, shape. Manually read from sheets.
sig={}
lines='''m_mid_artist|dark|short wavy|short beard|oval
m_mid_barista|dark brown|short swept|short beard|round
m_mid_business|salt pepper|short swept|short beard|square
m_mid_captain|grey black|mostly concealed by cap|full beard|long
m_mid_chef|dark|short receding|moustache|round
m_mid_conductor|dark|concealed by cap|moustache|long
m_mid_cook|dark|bald crown|thick moustache|round
m_mid_doctor|dark grey|short side part|short beard moustache|oval
m_mid_driver|dark|short receding|stubble|square
m_mid_fixer|dark brown|short wavy|short beard moustache|oval
m_mid_guard|dark|concealed by cap|moustache stubble|long
m_mid_lawyer|dark|short swept|none|long
m_mid_lecturer|dark grey|receding short|short beard moustache|oval
m_mid_merchant|salt pepper|short swept|full beard|long
m_mid_nurse|dark|short swept|none|long
m_mid_officer|dark|short side part|none|oval
m_mid_photographer|dark brown|short wavy|short beard moustache|oval
m_mid_policeman|dark|short receding|none|long
m_mid_resident|dark|short receding|none|long
m_mid_roadworker|dark brown|short swept|short beard moustache|square
m_mid_sailor|salt pepper|short wavy|full beard|long
m_mid_teacher|dark grey|short|moustache stubble|long
m_mid_technician|dark|concealed by cap|moustache|oval
m_mid_tycoon|dark brown|short swept|short beard moustache|square
m_old_bakerman|grey|bald crown|short beard|round
m_old_boss|dark grey|receding swept|moustache|round
m_old_butler|dark grey|bald crown|moustache|long
m_old_captain|grey|concealed by cap|full beard|round
m_old_cleric|white|concealed by turban|long full beard|long
m_old_farmer|grey|concealed by cap|moustache|long
m_old_fisher|grey|concealed by knit cap|moustache|square
m_old_flatcap|grey|concealed by cap|moustache|square
m_old_gardener|grey|short|moustache|long
m_old_grandpa|white|short curly|none|round
m_old_jurist|grey|short receding|none|square
m_old_painter|grey|medium wavy|short beard moustache|long
m_old_physician|grey white|short swept|short beard moustache|oval
m_old_professor|white grey|medium swept|full beard|long
m_old_rich|grey|short swept|none|square
m_old_schoolmaster|grey|short receding|moustache|long
m_old_scientist|dark grey|short swept|none|oval
m_old_tailor|grey|short receding|moustache|long
m_old_warden|grey|short side part|moustache|round
m_old_woolcap|grey|concealed by knit cap|stubble|long
m_young_athlete|dark|short side swept|none|square
m_young_boxer|dark brown|short curly|stubble|square
m_young_casual|dark|short swept|short beard|square
m_young_conscript|dark|short cropped|none|oval
m_young_courier|dark brown|short wavy|stubble|square
m_young_designer|dark brown|short wavy|short beard|round
m_young_dj|dark|short swept|stubble|oval
m_young_it|dark|short wavy|short beard|oval
m_young_student|dark|short wavy|light stubble|long
m_young_undergrad|dark|short wavy|light stubble|oval
m_young_waiter|dark|short swept|none|oval
m_young_worker|dark|short wavy|short beard|square
m_mid_researcher|dark grey temples|short wavy|moustache|oval
m_mid_worker|dark|short wavy|stubble|oval'''
for line in lines.splitlines():
 k,*v=line.split('|');sig[k]=v
round_f=set('f_mid_baker f_mid_curator f_mid_housewife f_mid_pastry f_old_baker f_old_cook f_old_retired f_old_retiree f_old_grandma'.split())
concealed=set('f_mid_archaeologist f_mid_business f_mid_chef f_mid_cleaner f_mid_doctor f_mid_guest f_mid_lawyer f_mid_manager f_mid_officer f_mid_pharmacist f_mid_teacher f_old_grandma f_old_rich f_old_shopkeeper f_young_athlete f_young_nurse f_young_receptionist f_young_researcher f_young_waitress f_mid_waitress'.split())
rows=[]
for p in sorted((R/'app/assets/portraits').glob('*.webp')):
 k=p.stem;assert k in wardrobe,k;g=k[0];old='_old_' in k
 if g=='m':color,style,beard,shape=sig[k]
 else:
  color='grey/silver' if old else 'dark brown';style='mostly concealed by headscarf' if k in concealed else 'wavy front strands visible under headscarf';beard='none';shape='round' if k in round_f else 'oval/angular'
 rows.append(dict(id=k,apparent_gender=g,apparent_age=ages[k],apparent_age_range=[ages[k]-5,ages[k]+5],hair_color=color,hair_style=style,facial_hair=beard,glasses=k in glasses,skin_tone='light to medium olive (warm amber illumination; approximate)',face_shape=shape,clothing=wardrobe[k],uniform=k in uniforms,uniform_type=uniforms.get(k),role_tags=[uniforms[k]] if k in uniforms else ['neutral'],sha256=hashlib.sha256(p.read_bytes()).hexdigest(),visual_review={'method':'human inspection of labelled contact sheet; three recovered portraits individually opened','date':'2026-11-07','status':'provisional editorial labels; not biometric measurements'}))
(R/'docs/art-registry.json').write_text(json.dumps({'schema_version':1,'age_note':'Apparent age is an editorial estimate anchored to portrait-ages.json, not a measurable biological age. Range is +/-5.','portraits':rows},ensure_ascii=False,indent=2)+'\n')
print(len(rows))
