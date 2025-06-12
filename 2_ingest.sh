#!/bin/bash

# Configuration
# OPENSEARCH_HOST="opense-clust-CePDyxTglAI8-6f22b7d87da3d2d1.elb.us-east-1.amazonaws.com"
# OPENSEARCH_PORT="80"
OPENSEARCH_HOST="localhost"
OPENSEARCH_PORT="9200"
INDEX_NAME="neural-search-index"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --index-name NAME               Index name (default: neural-search-index)"
    echo "  --help                          Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Ingest documents to default index:"
    echo "  $0"
    echo ""
    echo "  # Ingest documents to custom index:"
    echo "  $0 --index-name my-test-index"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --index-name)
      INDEX_NAME="$2"
      shift 2
      ;;
    --help)
      show_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo ""
      show_usage
      exit 1
      ;;
  esac
done

echo "Ingesting Test Documents for Semantic Highlighting"
echo "Target Index: ${INDEX_NAME}"

# Array of medical documents
declare -a DOCUMENTS=(
    "Diabetes mellitus is a metabolic disorder characterized by chronic hyperglycemia due to defects in insulin secretion, insulin action, or both. Type 1 diabetes requires insulin replacement therapy, while type 2 diabetes management includes lifestyle modifications, oral medications like metformin, and insulin when necessary. Complications include diabetic retinopathy, nephropathy, and neuropathy. Recent advances in continuous glucose monitoring and insulin pump therapy have significantly improved glycemic control and quality of life for patients."

    "Hypertension affects nearly one billion people worldwide and is a leading risk factor for cardiovascular disease. First-line treatments include ACE inhibitors, angiotensin receptor blockers, calcium channel blockers, and thiazide diuretics. Lifestyle interventions such as sodium restriction, weight loss, and regular exercise are essential components of management. Resistant hypertension may require combination therapy and evaluation for secondary causes."

    "Chronic obstructive pulmonary disease encompasses emphysema and chronic bronchitis, primarily caused by smoking. Treatment strategies include bronchodilators such as beta-2 agonists and anticholinergics, inhaled corticosteroids for severe cases, and pulmonary rehabilitation. Smoking cessation remains the most effective intervention to slow disease progression. Oxygen therapy and lung volume reduction surgery may benefit selected patients with advanced disease."

    "Rheumatoid arthritis is an autoimmune inflammatory disorder affecting synovial joints. Disease-modifying antirheumatic drugs including methotrexate, hydroxychloroquine, and biologics like TNF inhibitors have revolutionized treatment outcomes. Early aggressive therapy can prevent joint destruction and improve long-term prognosis. Corticosteroids provide rapid symptom relief but are reserved for short-term use due to side effects."

    "Osteoporosis is characterized by decreased bone density and increased fracture risk, particularly in postmenopausal women. Treatment options include bisphosphonates, denosumab, and selective estrogen receptor modulators. Calcium and vitamin D supplementation, weight-bearing exercise, and fall prevention strategies are crucial preventive measures. Newer anabolic agents like teriparatide can stimulate bone formation in severe cases."

    "Asthma is a chronic respiratory condition involving airway inflammation and bronchospasm. Controller medications include inhaled corticosteroids and long-acting beta-agonists, while rescue inhalers contain short-acting bronchodilators. Personalized treatment plans based on symptom severity and trigger identification are essential. Biologic therapies targeting specific inflammatory pathways offer hope for severe, uncontrolled asthma."

    "Migraine headaches affect approximately 12% of the population, with significant impact on quality of life. Acute treatments include triptans, NSAIDs, and ergot alkaloids, while preventive therapies encompass beta-blockers, anticonvulsants, and CGRP inhibitors. Lifestyle modifications including sleep hygiene, stress management, and trigger avoidance play important roles in management. New CGRP antagonists have shown promising results in clinical trials."

    "Inflammatory bowel disease includes Crohn's disease and ulcerative colitis, both requiring complex management strategies. Aminosalicylates, corticosteroids, immunomodulators, and biologic agents form the therapeutic armamentarium. Nutritional support and surgical intervention may be necessary for complications. Personalized medicine approaches based on genetic markers and drug level monitoring are emerging treatment paradigms."

    "Chronic kidney disease progression can be slowed through blood pressure control, proteinuria reduction, and glycemic management in diabetic patients. ACE inhibitors and ARBs provide renoprotective effects beyond blood pressure lowering. Dietary protein restriction, phosphate binders, and erythropoiesis-stimulating agents address metabolic complications. Renal replacement therapy planning should begin early in advanced stages."

    "Multiple sclerosis is a demyelinating autoimmune disease with relapsing-remitting or progressive courses. Disease-modifying therapies include interferons, glatiramer acetate, and newer oral agents like fingolimod and dimethyl fumarate. High-efficacy treatments such as natalizumab and alemtuzumab are reserved for aggressive disease. Symptomatic management addresses spasticity, fatigue, and cognitive dysfunction."

    "Epilepsy management requires careful antiepileptic drug selection based on seizure type and patient characteristics. Traditional agents like phenytoin and carbamazepine remain effective, while newer drugs offer improved tolerability profiles. Refractory epilepsy may benefit from surgical resection, vagal nerve stimulation, or ketogenic diet therapy. Genetic testing increasingly informs treatment decisions in specific epilepsy syndromes."

    "Parkinson's disease involves dopaminergic neuron loss in the substantia nigra, leading to motor symptoms. Levodopa remains the gold standard treatment, often combined with carbidopa to reduce peripheral side effects. Dopamine agonists, MAO-B inhibitors, and COMT inhibitors provide additional therapeutic options. Deep brain stimulation offers significant benefit for advanced disease with motor fluctuations."

    "Schizophrenia requires antipsychotic medications targeting dopamine and serotonin receptors. Atypical antipsychotics like risperidone and olanzapine offer improved side effect profiles compared to traditional agents. Psychosocial interventions including cognitive behavioral therapy and social skills training enhance functional outcomes. Long-acting injectable formulations improve medication adherence in this challenging population."

    "Bipolar disorder management involves mood stabilizers such as lithium, valproate, and lamotrigine for maintenance therapy. Acute manic episodes may require antipsychotics or benzodiazepines for rapid stabilization. Antidepressants should be used cautiously due to risk of triggering mania. Psychoeducation and psychotherapy complement pharmacological interventions for optimal outcomes."

    "Anxiety disorders encompass generalized anxiety, panic disorder, and social phobia, each requiring tailored treatment approaches. Selective serotonin reuptake inhibitors and serotonin-norepinephrine reuptake inhibitors serve as first-line pharmacotherapy. Benzodiazepines provide rapid relief but carry dependence risks with long-term use. Cognitive behavioral therapy demonstrates comparable efficacy to medications with durable benefits."

    "Stroke treatment depends on rapid recognition and intervention within therapeutic windows. Thrombolytic therapy with tissue plasminogen activator can restore perfusion in ischemic strokes when administered within 4.5 hours. Mechanical thrombectomy extends treatment options for large vessel occlusions. Secondary prevention includes antiplatelet agents, anticoagulants for atrial fibrillation, and aggressive risk factor modification."

    "Heart failure management has evolved with evidence-based therapies improving survival and quality of life. ACE inhibitors, beta-blockers, and aldosterone antagonists form the cornerstone of treatment for reduced ejection fraction. Diuretics provide symptomatic relief for fluid overload. Newer agents like SGLT2 inhibitors and angiotensin receptor-neprilysin inhibitors offer additional benefits."

    "Atrial fibrillation increases stroke risk and requires anticoagulation in most patients. Direct oral anticoagulants have largely replaced warfarin due to improved safety profiles and convenience. Rate control with beta-blockers or calcium channel blockers is often preferred over rhythm control strategies. Catheter ablation may cure paroxysmal atrial fibrillation in selected patients."

    "Hepatitis C has become a curable disease with direct-acting antiviral agents achieving sustained virologic response rates exceeding 95%. Sofosbuvir-based regimens have revolutionized treatment with shortened duration and minimal side effects. Pan-genotypic combinations eliminate the need for genotype testing in many cases. Treatment prioritization focuses on patients with advanced fibrosis and high transmission risk."

    "Osteoarthritis affects weight-bearing joints and hands, causing pain and functional impairment. Non-pharmacologic interventions including exercise, weight loss, and physical therapy form the foundation of management. Topical and oral NSAIDs provide symptomatic relief while acetaminophen offers a safer alternative for elderly patients. Intra-articular corticosteroid injections and hyaluronic acid may benefit selected patients, with joint replacement reserved for end-stage disease."

    "Tuberculosis remains a global health challenge, particularly in immunocompromised populations. Standard treatment involves a four-drug regimen of isoniazid, rifampin, ethambutol, and pyrazinamide for the initial phase, followed by continuation therapy with isoniazid and rifampin. Directly observed therapy ensures medication adherence and reduces resistance development. Latent tuberculosis treatment with isoniazid or rifampin prevents progression to active disease."

    "Pneumonia treatment varies based on causative organisms and disease severity. Community-acquired pneumonia typically responds to macrolides or beta-lactam antibiotics, while hospital-acquired infections may require broader spectrum coverage. Supportive care includes oxygen therapy, fluid management, and respiratory support. Pneumococcal and influenza vaccines provide effective prevention strategies."

    "Urinary tract infections predominantly affect women and require appropriate antibiotic selection based on local resistance patterns. First-line treatments include nitrofurantoin, trimethoprim-sulfamethoxazole, and fosfomycin for uncomplicated cystitis. Pyelonephritis necessitates systemic therapy with fluoroquinolones or cephalosporins. Prophylactic antibiotics may benefit patients with recurrent infections."

    "Gastroesophageal reflux disease affects millions worldwide and can lead to serious complications if untreated. Proton pump inhibitors effectively suppress acid production and promote healing of erosive esophagitis. H2 receptor antagonists provide alternative therapy for mild symptoms. Lifestyle modifications including dietary changes, weight loss, and elevation of the head of bed complement medical therapy."

    "Hypothyroidism requires lifelong thyroid hormone replacement therapy with levothyroxine. Dosing should be individualized based on TSH levels, patient age, and comorbidities. Symptoms improve gradually over several weeks to months with adequate replacement. Special considerations apply during pregnancy, with increased hormone requirements and frequent monitoring."

    "Hyperthyroidism management depends on the underlying cause and patient characteristics. Antithyroid medications like methimazole and propylthiouracil provide medical therapy options. Radioactive iodine ablation offers definitive treatment for Graves' disease and toxic nodular goiter. Beta-blockers provide symptomatic relief from adrenergic symptoms while definitive therapy takes effect."

    "Anemia evaluation requires identification of the underlying cause before initiating treatment. Iron deficiency anemia responds to oral or intravenous iron supplementation. Vitamin B12 and folate deficiencies require specific vitamin replacement therapy. Chronic kidney disease-related anemia may benefit from erythropoiesis-stimulating agents and iron supplementation."

    "Deep vein thrombosis and pulmonary embolism constitute venous thromboembolism requiring immediate anticoagulation. Direct oral anticoagulants have simplified treatment with fixed dosing and minimal monitoring requirements. Duration of therapy depends on risk factors and bleeding risk assessment. Compression stockings and early mobilization prevent post-thrombotic syndrome."

    "Sepsis represents a life-threatening organ dysfunction caused by dysregulated host response to infection. Early recognition and prompt antibiotic administration within one hour significantly improve outcomes. Fluid resuscitation and vasopressor support maintain hemodynamic stability. Source control through drainage or debridement is essential when feasible."

    "Acute myocardial infarction requires immediate reperfusion therapy to minimize myocardial damage. Primary percutaneous coronary intervention is preferred when available within appropriate time frames. Thrombolytic therapy provides alternative reperfusion for patients without access to catheterization. Dual antiplatelet therapy, beta-blockers, and ACE inhibitors improve long-term outcomes."

    "Chronic pain management requires multimodal approaches addressing physical, psychological, and social factors. Non-opioid analgesics including acetaminophen and NSAIDs form the foundation of treatment. Adjuvant medications like anticonvulsants and antidepressants target neuropathic pain components. Physical therapy, cognitive behavioral therapy, and interventional procedures complement pharmacological interventions."

    "Inflammatory bowel disease flares require prompt intervention to prevent complications and maintain remission. Corticosteroids provide rapid symptom relief for moderate to severe exacerbations. Immunomodulators and biologic agents offer steroid-sparing maintenance therapy. Nutritional support and surgical consultation may be necessary for refractory cases or complications."

    "Skin cancer prevention through sun protection measures and regular dermatologic screening can reduce morbidity and mortality. Melanoma treatment has been revolutionized by immune checkpoint inhibitors and targeted therapies for metastatic disease. Mohs surgery provides optimal outcomes for basal and squamous cell carcinomas in high-risk locations. Early detection remains crucial for all skin cancer types."

    "Chronic fatigue syndrome presents diagnostic and therapeutic challenges due to unclear etiology and lack of specific biomarkers. Management focuses on symptom relief and functional improvement through graded exercise therapy and cognitive behavioral interventions. Sleep hygiene, orthostatic intolerance management, and treatment of comorbid conditions may provide benefit. Pacing activities prevents post-exertional malaise."

    "Fibromyalgia affects millions of patients worldwide with widespread musculoskeletal pain and associated symptoms. Tricyclic antidepressants, SNRIs, and anticonvulsants provide pain relief through central nervous system modulation. Non-pharmacologic interventions including exercise, stress reduction, and sleep hygiene are essential components. Patient education and multidisciplinary care improve outcomes and quality of life."

    "Irritable bowel syndrome management focuses on symptom relief and dietary modifications. Fiber supplementation may benefit constipation-predominant patients, while antispasmodics provide cramping relief. Probiotics show promise for some patients with specific strains demonstrating efficacy. Low FODMAP diets can identify trigger foods and improve symptoms in many patients."

    "Obesity treatment requires comprehensive lifestyle interventions addressing diet, physical activity, and behavioral factors. Pharmacotherapy with orlistat, liraglutide, or combination medications may assist weight loss in appropriate candidates. Bariatric surgery provides effective long-term weight reduction for severely obese patients. Multidisciplinary teams optimize outcomes through coordinated care."

    "Sleep apnea diagnosis requires overnight sleep studies to assess severity and guide treatment decisions. Continuous positive airway pressure remains the gold standard therapy for obstructive sleep apnea. Alternative treatments include oral appliances, positional therapy, and surgical interventions for selected patients. Weight loss significantly improves symptoms in overweight and obese patients."

    "Allergic rhinitis affects quality of life and productivity but responds well to appropriate therapy. Intranasal corticosteroids provide the most effective single-agent treatment for persistent symptoms. Antihistamines offer relief for intermittent symptoms and complement nasal corticosteroids. Allergen avoidance measures and immunotherapy address underlying sensitivities."

    "Vertigo evaluation requires careful history taking to differentiate peripheral from central causes. Benign paroxysmal positional vertigo responds to repositioning maneuvers like the Epley procedure. Vestibular neuritis may benefit from corticosteroids when started early. Chronic symptoms may require vestibular rehabilitation therapy for compensation."

    "Peripheral neuropathy has multiple etiologies requiring targeted treatment approaches. Diabetic neuropathy management emphasizes glycemic control and symptomatic pain relief with anticonvulsants or tricyclic antidepressants. Vitamin deficiencies should be identified and corrected. Foot care education prevents serious complications in diabetic patients."

    "Gout results from hyperuricemia and uric acid crystal deposition in joints and tissues. Acute attacks respond to colchicine, NSAIDs, or corticosteroids for rapid pain relief. Urate-lowering therapy with allopurinol or febuxostat prevents future attacks and tophi formation. Dietary modifications reducing purine intake complement medical therapy."

    "Celiac disease requires strict gluten-free diet adherence for symptomatic improvement and prevention of complications. Nutritional deficiencies are common at diagnosis and require supplementation. Follow-up monitoring includes symptom assessment, antibody levels, and repeat biopsy in selected cases. Dietitian consultation facilitates dietary compliance and meal planning."

    "Hepatitis B management depends on viral replication status and liver inflammation. Chronic infection with high viral loads benefits from antiviral therapy with tenofovir or entecavir. Immune-tolerant patients require monitoring without treatment. Vaccination provides effective prevention, and post-exposure prophylaxis reduces transmission risk."

    "Psoriasis treatment has expanded dramatically with biologic therapies targeting specific inflammatory pathways. Topical corticosteroids and vitamin D analogs remain first-line treatments for limited disease. Phototherapy provides effective systemic treatment without systemic medication risks. Methotrexate and cyclosporine offer traditional systemic options for extensive psoriasis."

    "Cataracts represent the leading cause of blindness worldwide but are readily treatable with surgical intervention. Phacoemulsification with intraocular lens implantation restores vision in most patients. Timing of surgery depends on functional impairment rather than visual acuity alone. Multifocal and toric lenses address presbyopia and astigmatism respectively."

    "Glaucoma requires early detection and treatment to prevent irreversible vision loss. Intraocular pressure reduction remains the primary therapeutic target with topical medications as first-line therapy. Laser trabeculoplasty provides effective pressure lowering in many patients. Surgical interventions are reserved for cases with inadequate medical or laser control."

    "Macular degeneration affects central vision and requires different approaches for dry and wet forms. Anti-VEGF injections have revolutionized wet macular degeneration treatment with vision preservation and improvement. Dry macular degeneration management focuses on nutritional supplementation and monitoring for conversion to wet form. Low vision aids maximize remaining visual function."

    "Benign prostatic hyperplasia affects most aging men and can significantly impact quality of life. Alpha-blockers provide rapid symptom relief by relaxing smooth muscle. 5-alpha reductase inhibitors reduce prostate size over time but require months for full effect. Surgical options include transurethral resection and newer minimally invasive procedures."

    "Erectile dysfunction evaluation requires assessment for cardiovascular and psychological causes. PDE-5 inhibitors provide effective oral therapy for most patients without contraindications. Vacuum devices, intracavernosal injections, and penile implants offer alternatives for refractory cases. Lifestyle modifications including exercise and smoking cessation improve outcomes."

    "Menopause management balances symptom relief with long-term health risks. Hormone replacement therapy effectively treats vasomotor symptoms but requires individualized risk-benefit assessment. Non-hormonal alternatives include SSRIs, gabapentin, and lifestyle modifications. Calcium and vitamin D supplementation along with weight-bearing exercise prevent osteoporosis."

    "Polycystic ovary syndrome requires comprehensive management addressing metabolic and reproductive aspects. Metformin improves insulin sensitivity and may restore ovulation in some patients. Combined oral contraceptives regulate menstrual cycles and reduce androgens. Fertility treatments include ovulation induction with clomiphene or gonadotropins."

    "Endometriosis causes significant pain and fertility issues requiring individualized treatment approaches. NSAIDs and hormonal contraceptives provide first-line symptom management. GnRH agonists offer more potent suppression for severe cases. Surgical intervention may be necessary for refractory symptoms or fertility preservation."

    "Infertility evaluation requires assessment of both partners to identify treatable causes. Ovulation induction with clomiphene or letrozole may restore fertility in anovulatory women. Intrauterine insemination increases pregnancy rates in certain conditions. In vitro fertilization provides hope for couples with tubal factors or severe male infertility."

    "Osteoporosis prevention begins early with adequate calcium and vitamin D intake throughout life. Dual-energy X-ray absorptiometry screening identifies at-risk individuals before fractures occur. Bisphosphonates remain first-line therapy for most patients with established osteoporosis. Fall prevention strategies reduce fracture risk independent of bone density."

    "Age-related hearing loss affects communication and quality of life but responds well to amplification. Hearing aids have improved dramatically with digital technology and directional microphones. Cochlear implants benefit patients with severe to profound hearing loss. Assistive listening devices enhance hearing in specific situations."

    "Alzheimer's disease research continues to seek disease-modifying therapies while current treatments provide modest symptomatic benefit. Cholinesterase inhibitors may slow cognitive decline in mild to moderate stages. Memantine offers an alternative mechanism for moderate to severe disease. Non-pharmacologic interventions support quality of life throughout the disease course."

    "Stroke rehabilitation begins immediately after acute treatment and continues for months to years. Physical therapy addresses motor deficits and mobility issues. Speech therapy helps with communication and swallowing problems. Occupational therapy focuses on activities of daily living and adaptive equipment needs."

    "Chronic obstructive pulmonary disease exacerbations require prompt treatment to prevent hospitalization and preserve lung function. Bronchodilators and systemic corticosteroids form the cornerstone of acute treatment. Antibiotics benefit patients with increased sputum purulence or bacterial infections. Oxygen therapy may be necessary for severe hypoxemia."

    "Wound healing requires assessment of underlying factors that may impair the normal process. Moist wound environment promotes faster healing compared to dry conditions. Debridement removes non-viable tissue and promotes granulation. Advanced wound care products including hydrocolloids and foam dressings optimize healing conditions."

    "Pressure ulcers are preventable complications requiring systematic assessment and intervention. Risk factors include immobility, moisture, friction, and nutritional deficits. Regular repositioning and pressure-relieving surfaces reduce incidence. Staging guides treatment decisions from conservative management to surgical intervention."

    "Medication adherence remains a significant challenge affecting treatment outcomes across all conditions. Patient education about medication importance and side effects improves compliance. Pill organizers, reminder systems, and simplified regimens reduce barriers to adherence. Healthcare provider communication and follow-up support medication-taking behaviors."

    "Preventive medicine emphasizes early detection and risk factor modification to prevent disease development. Routine screening tests identify asymptomatic conditions amenable to early intervention. Vaccination programs prevent infectious diseases across all age groups. Lifestyle counseling addresses modifiable risk factors for chronic diseases."

    "Palliative care focuses on quality of life improvement for patients with serious illnesses. Pain and symptom management requires comprehensive assessment and multimodal interventions. Psychosocial support addresses emotional and spiritual needs of patients and families. Goals of care discussions ensure treatment alignment with patient values and preferences."

    "Addiction medicine recognizes substance use disorders as chronic brain diseases requiring comprehensive treatment. Medication-assisted treatment combines pharmacotherapy with behavioral interventions for optimal outcomes. Naloxone distribution and education prevent overdose deaths. Recovery support services facilitate long-term sobriety and community reintegration."

    "Infectious disease prevention through hand hygiene, vaccination, and antimicrobial stewardship reduces healthcare-associated infections. Empiric antibiotic therapy requires knowledge of local resistance patterns and patient risk factors. Duration of therapy should be optimized to prevent resistance development. Isolation precautions prevent transmission of multidrug-resistant organisms."

    "Mental health integration into primary care improves access and outcomes for common psychiatric conditions. Screening tools identify depression and anxiety in routine clinical encounters. Collaborative care models utilize care coordinators and psychiatric consultants. Telepsychiatry expands access to mental health services in underserved areas."

    "Geriatric medicine addresses the unique healthcare needs of older adults with multiple comorbidities. Comprehensive geriatric assessment identifies frailty and functional decline. Medication reconciliation prevents adverse drug events and inappropriate prescribing. Fall prevention strategies reduce injury risk and maintain independence."

    "Pediatric medicine requires age-appropriate treatment modifications and developmental considerations. Growth and development monitoring identifies abnormalities requiring intervention. Immunization schedules protect against vaccine-preventable diseases. Anticipatory guidance prepares families for upcoming developmental milestones and safety concerns."

    "Women's health encompasses reproductive, hormonal, and general health issues throughout the lifespan. Preconception counseling optimizes pregnancy outcomes through risk factor modification. Routine gynecologic care includes cervical cancer screening and contraceptive counseling. Mammography screening reduces breast cancer mortality through early detection."

    "Pneumothorax can be spontaneous or traumatic, requiring immediate recognition and intervention. Primary spontaneous pneumothorax commonly affects young, tall, thin males. Needle decompression provides emergency relief for tension pneumothorax. Chest tube insertion is the definitive treatment for significant air collections, with pleurodesis considered for recurrent cases."

    "Acute pancreatitis presents with severe epigastric pain and elevated pancreatic enzymes. Supportive care includes aggressive fluid resuscitation, pain control, and nutritional support. Severe cases may develop complications including pseudocysts, necrosis, or organ failure. Gallstone pancreatitis requires cholecystectomy after acute episode resolution."

    "Diverticulitis affects the sigmoid colon in Western populations and requires antibiotic therapy for uncomplicated cases. Complicated diverticulitis with perforation, abscess, or obstruction may require surgical intervention. High-fiber diet and adequate hydration help prevent recurrent episodes. Colonoscopy should be delayed until inflammation resolves."

    "Appendicitis remains the most common surgical emergency, requiring prompt diagnosis and intervention. Classic presentation includes periumbilical pain migrating to the right lower quadrant with nausea and fever. CT scan provides accurate diagnosis in atypical presentations. Laparoscopic appendectomy offers advantages over open surgery including reduced recovery time."

    "Gallbladder disease encompasses cholelithiasis, cholecystitis, and biliary complications. Right upper quadrant pain after fatty meals suggests gallbladder pathology. Ultrasound is the initial imaging modality of choice. Laparoscopic cholecystectomy is the gold standard treatment for symptomatic cholelithiasis and acute cholecystitis."

    "Peptic ulcer disease results from Helicobacter pylori infection or NSAID use in most cases. Triple therapy with proton pump inhibitor and two antibiotics eradicates H. pylori effectively. NSAID-induced ulcers require acid suppression and medication discontinuation when possible. Complications include bleeding, perforation, and gastric outlet obstruction."

    "Cirrhosis represents end-stage liver disease with portal hypertension and hepatocellular dysfunction. Complications include ascites, variceal bleeding, hepatic encephalopathy, and hepatorenal syndrome. Liver transplantation is the definitive treatment for decompensated cirrhosis. Alcohol cessation is crucial for alcoholic liver disease progression prevention."

    "Chronic kidney disease staging guides management and prognosis assessment. Early stages focus on blood pressure control and proteinuria reduction. Advanced stages require management of mineral bone disorder, anemia, and metabolic acidosis. Dialysis access planning should begin when GFR falls below 30 mL/min/1.73m²."

    "Thyroid nodules are common incidental findings requiring systematic evaluation. Fine needle aspiration biopsy determines malignancy risk based on cytological features. Benign nodules may be monitored with serial ultrasound examinations. Surgical resection is indicated for malignant or suspicious lesions and large symptomatic nodules."

    "Breast cancer screening with mammography reduces mortality in women aged 50-74 years. Genetic testing for BRCA mutations guides high-risk patient management. Treatment involves multidisciplinary approach including surgery, chemotherapy, radiation, and hormonal therapy. Sentinel lymph node biopsy has replaced routine axillary dissection for staging."

    "Prostate cancer screening remains controversial due to overdiagnosis concerns. PSA testing and digital rectal examination guide screening decisions. Active surveillance is appropriate for low-risk disease. Treatment options include surgery, radiation therapy, and androgen deprivation therapy based on risk stratification."

    "Colorectal cancer screening prevents disease through polyp detection and removal. Colonoscopy remains the gold standard with 10-year intervals for average-risk individuals. Fecal immunochemical testing provides non-invasive screening alternative. Early-stage disease has excellent prognosis with surgical resection."

    "Lung cancer is the leading cause of cancer death worldwide with strong smoking association. CT screening reduces mortality in high-risk smokers. Molecular testing guides targeted therapy selection for advanced disease. Immunotherapy has revolutionized treatment for metastatic non-small cell lung cancer."

    "Cervical cancer is preventable through HPV vaccination and regular screening. Pap smears detect precancerous lesions amenable to local treatment. HPV testing has improved screening sensitivity and allowed interval extension. Early-stage disease is highly curable with surgery or radiation therapy."

    "Ovarian cancer often presents at advanced stages due to nonspecific symptoms. CA-125 levels and pelvic imaging aid in diagnosis but are not useful for screening. Surgical staging and debulking followed by chemotherapy form the treatment backbone. BRCA mutations increase risk and influence treatment decisions."

    "Bladder cancer predominantly affects older males with smoking history. Hematuria is the most common presenting symptom requiring urologic evaluation. Transurethral resection provides diagnosis and treatment for non-muscle invasive disease. Muscle-invasive cancer requires radical cystectomy or chemoradiation therapy."

    "Pancreatic cancer has poor prognosis due to late presentation and aggressive biology. Whipple procedure offers curative potential for resectable disease. Adjuvant chemotherapy improves survival even after complete resection. Palliative care focuses on symptom management for advanced disease."

    "Leukemia encompasses acute and chronic forms affecting different blood cell lineages. Acute leukemias require immediate intensive chemotherapy. Chronic lymphocytic leukemia may be monitored without treatment in early stages. Stem cell transplantation offers curative potential for selected patients."

    "Lymphoma includes Hodgkin and non-Hodgkin subtypes with different treatment approaches. PET scans guide staging and treatment response assessment. Rituximab has improved outcomes for B-cell lymphomas. Radiation therapy may be used alone or combined with chemotherapy."

    "Melanoma incidence is rising worldwide with UV exposure as the primary risk factor. Surgical excision with appropriate margins is the primary treatment. Sentinel lymph node biopsy guides staging for intermediate-thickness lesions. Immunotherapy and targeted therapy have transformed metastatic disease treatment."

    "Sarcomas are rare mesenchymal tumors requiring specialized management. Complete surgical resection is the primary treatment when feasible. Radiation therapy may be used for local control in high-risk cases. Chemotherapy response varies significantly among different sarcoma subtypes."

    "Brain tumors require multidisciplinary management including neurosurgery, radiation, and medical oncology. Glioblastoma is the most aggressive primary brain tumor with poor prognosis. Stereotactic radiosurgery offers precise treatment for small lesions. Corticosteroids reduce perilesional edema and symptoms."

    "Spinal cord injuries require immediate stabilization and high-dose corticosteroids within 8 hours. Complete injuries have poor functional recovery prospects. Rehabilitation focuses on maximizing independence and preventing complications. Autonomic dysreflexia is a life-threatening complication requiring prompt recognition."

    "Traumatic brain injury severity guides treatment decisions and prognostic assessment. Intracranial pressure monitoring is indicated for severe cases. Decompressive craniectomy may be life-saving for refractory intracranial hypertension. Cognitive rehabilitation addresses long-term functional impairments."

    "Burn injuries require immediate assessment of total body surface area and depth. Fluid resuscitation follows standardized formulas to prevent shock. Wound care includes debridement, topical antimicrobials, and grafting procedures. Rehabilitation addresses contractures and functional limitations."

    "Fractures require appropriate reduction and immobilization to ensure proper healing. Open fractures need urgent irrigation, debridement, and antibiotic therapy. Compartment syndrome is a surgical emergency requiring immediate fasciotomy. Non-union may require bone grafting or electrical stimulation."

    "Dislocations require prompt reduction to minimize neurovascular complications. Shoulder dislocations are most common and may be associated with rotator cuff tears. Hip dislocations in young patients usually result from high-energy trauma. Recurrent dislocations may require surgical stabilization."

    "Tendon injuries require careful evaluation and surgical repair when indicated. Achilles tendon ruptures may be treated surgically or conservatively. Rotator cuff tears increase with age and may benefit from arthroscopic repair. Hand tendon injuries require specialized surgical expertise."

    "Ligament injuries commonly affect the knee and ankle joints. ACL tears often require surgical reconstruction in active individuals. Ankle sprains are treated conservatively with rest, ice, compression, and elevation. Chronic instability may develop without proper rehabilitation."

    "Joint replacements provide excellent pain relief and functional improvement for end-stage arthritis. Hip replacements have high success rates and long-term durability. Knee replacements may be partial or total depending on disease extent. Complications include infection, loosening, and dislocation."

    "Carpal tunnel syndrome results from median nerve compression at the wrist. Conservative treatment includes splinting, activity modification, and steroid injections. Surgical release provides definitive treatment for severe or refractory cases. Early diagnosis and treatment prevent permanent nerve damage."

    "Plantar fasciitis causes heel pain that is worst with first steps in the morning. Conservative treatment includes stretching, orthotics, and anti-inflammatory medications. Steroid injections may provide temporary relief for severe cases. Surgery is rarely necessary and reserved for refractory symptoms."

    "Lower back pain affects most adults at some point in their lives. Acute episodes usually resolve with conservative treatment including activity modification and pain medications. Red flag symptoms require urgent evaluation for serious underlying pathology. Chronic pain may benefit from physical therapy and multidisciplinary management."

    "Neck pain often results from poor posture, muscle strain, or degenerative changes. Whiplash injuries from motor vehicle accidents may cause persistent symptoms. Physical therapy and ergonomic modifications help prevent recurrent episodes. Cervical radiculopathy may require surgical intervention for nerve compression."

    "Sports injuries commonly affect young athletes and weekend warriors. Concussions require careful evaluation and graduated return-to-play protocols. Overuse injuries result from repetitive stress and inadequate recovery time. Proper conditioning and equipment reduce injury risk."

    "Pediatric injuries have unique considerations due to ongoing growth and development. Growth plate injuries may affect future bone development. Child abuse must be considered in certain injury patterns. Treatment modifications account for smaller size and different healing patterns."

    "Geriatric trauma patients face increased morbidity and mortality risks. Osteoporotic fractures may occur with minimal trauma. Medication effects and comorbidities complicate management. Early mobilization prevents complications and improves outcomes."

    "Emergency medicine encompasses acute care for undifferentiated patients. Triage systems prioritize care based on acuity and resource availability. Advanced cardiac life support protocols guide resuscitation efforts. Emergency physicians must maintain broad knowledge across multiple specialties."

    "Critical care medicine manages patients with life-threatening conditions. Mechanical ventilation supports respiratory failure patients. Vasopressors maintain blood pressure in shock states. Sedation and analgesia require careful titration to avoid complications."

    "Anesthesiology ensures safe perioperative care through careful monitoring and drug administration. Preoperative evaluation identifies risk factors and optimizes patient condition. Regional anesthesia provides excellent pain control with fewer side effects. Postoperative pain management improves patient satisfaction and outcomes."

    "Radiology provides essential diagnostic information through various imaging modalities. CT scans offer rapid evaluation of trauma patients and acute abdominal pain. MRI provides superior soft tissue contrast for musculoskeletal and neurologic conditions. Interventional radiology offers minimally invasive treatment options."

    "Pathology provides definitive diagnosis through tissue examination. Frozen sections guide surgical decisions during operations. Immunohistochemistry helps classify tumors and guide treatment. Molecular pathology increasingly influences cancer therapy selection."

    "Laboratory medicine provides objective data to guide clinical decisions. Complete blood counts reveal hematologic abnormalities. Basic metabolic panels assess electrolyte and kidney function. Cardiac enzymes help diagnose myocardial infarction."

    "Physical therapy restores function and mobility after injury or illness. Therapeutic exercises strengthen muscles and improve range of motion. Gait training helps patients regain safe ambulation. Manual therapy techniques reduce pain and improve tissue flexibility."

    "Occupational therapy focuses on activities of daily living and work-related tasks. Adaptive equipment helps patients overcome functional limitations. Cognitive rehabilitation addresses memory and executive function deficits. Home safety evaluations prevent falls and injuries."

    "Speech therapy addresses communication and swallowing disorders. Stroke patients often require speech therapy for aphasia or dysarthria. Swallowing evaluations prevent aspiration pneumonia. Voice therapy helps patients with vocal cord paralysis or nodules."

    "Nutrition counseling optimizes dietary intake for various medical conditions. Diabetic patients learn carbohydrate counting and meal planning. Heart disease patients benefit from low-sodium, low-fat diets. Malnutrition screening identifies at-risk hospitalized patients."

    "Social work addresses psychosocial factors affecting patient care. Discharge planning ensures safe transitions from hospital to home. Financial counseling helps patients access necessary medications and treatments. Support groups provide peer connections for chronic disease management."

    "Nursing care encompasses direct patient care, education, and advocacy. Medication administration requires careful attention to safety protocols. Patient monitoring detects clinical changes requiring intervention. Patient education promotes self-care and treatment adherence."

    "Pharmacy services ensure safe and effective medication use. Drug interactions screening prevents adverse events. Dosing adjustments account for kidney and liver function. Medication reconciliation prevents errors during transitions of care."

    "Case management coordinates care across multiple providers and settings. Insurance authorization ensures coverage for necessary treatments. Resource identification connects patients with community services. Quality improvement initiatives enhance patient safety and outcomes."
)

echo -e "\n${GREEN}Starting document ingestion...${NC}"

# Ingest documents
for i in "${!DOCUMENTS[@]}"; do
    doc_id=$((i + 1))
    echo -n "Indexing document ${doc_id}/120..."
    
    DOC_RESPONSE=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_doc/${doc_id}" -H 'Content-Type: application/json' -d"{
        \"text\": \"${DOCUMENTS[i]}\"
    }")
    
    if [[ $DOC_RESPONSE == *"error"* ]]; then
        echo -e "\n${RED}Error indexing document ${doc_id}: $DOC_RESPONSE${NC}"
        exit 1
    fi
    echo " Done"
done

echo -e "\n${GREEN}All documents indexed successfully!${NC}"

# Refresh the index
echo -e "${GREEN}Refreshing index...${NC}"
curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_refresh" > /dev/null

# Verify document count
echo -e "${GREEN}Verifying document count...${NC}"
COUNT_RESPONSE=$(curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_count")
TOTAL_DOCS=$(echo $COUNT_RESPONSE | grep -o '"count":[0-9]*' | cut -d':' -f2)

echo -e "\n${GREEN}Ingestion completed!${NC}"
echo "Total documents in index: ${TOTAL_DOCS}"
echo "Index: ${INDEX_NAME}" 