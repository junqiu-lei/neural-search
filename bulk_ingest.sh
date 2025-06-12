#!/bin/bash

echo "=== 大量数据摄取脚本 ==="
echo "目标：增加索引中的文档数量以改善基准测试"
echo ""

INDEX_NAME="neural-search-index"
OPENSEARCH_HOST="localhost"
OPENSEARCH_PORT="9200"

# 医学相关的文档模板
DOCUMENT_TEMPLATES=(
    "Diabetes management requires comprehensive care including glycemic control, cardiovascular risk reduction, and complication prevention. Modern treatment approaches utilize continuous glucose monitoring, insulin pumps, and lifestyle modifications. Patient education empowers individuals to manage their condition effectively."

    "Hypertension treatment focuses on lifestyle modifications and antihypertensive medications to reduce cardiovascular events. Regular monitoring ensures blood pressure targets are achieved. Combination therapy may be necessary for resistant hypertension."

    "Cancer immunotherapy has revolutionized oncology treatment by harnessing the immune system to fight malignancies. Checkpoint inhibitors, CAR-T cell therapy, and cancer vaccines represent major therapeutic advances. Personalized medicine approaches optimize treatment selection."

    "Cardiovascular disease prevention emphasizes risk factor modification including smoking cessation, exercise, and dietary changes. Statins reduce cholesterol and cardiovascular events. Blood pressure control prevents heart attacks and strokes."

    "Antibiotic resistance poses growing challenges in infectious disease treatment. Antimicrobial stewardship programs promote appropriate usage patterns. New antibiotics and alternative therapies address resistant organisms."

    "Mental health treatment integrates psychotherapy and pharmacotherapy approaches. Cognitive behavioral therapy effectively treats depression and anxiety. Psychiatric medications require careful monitoring for efficacy and side effects."

    "Surgical innovations include minimally invasive techniques, robotic surgery, and enhanced recovery protocols. Preoperative optimization improves outcomes and reduces complications. Postoperative care focuses on pain management and early mobilization."

    "Neurological disorders require specialized diagnostic approaches and treatment strategies. Brain imaging guides diagnosis and treatment planning. Rehabilitation maximizes functional recovery after neurological injuries."

    "Respiratory diseases encompass asthma, COPD, and pulmonary infections requiring targeted therapies. Inhaled medications deliver treatment directly to affected airways. Pulmonary rehabilitation improves exercise tolerance and quality of life."

    "Gastrointestinal conditions affect digestion, absorption, and elimination processes. Endoscopic procedures enable diagnosis and therapeutic interventions. Dietary modifications complement medical treatments for optimal outcomes."
)

# 疾病名称变体
DISEASE_VARIANTS=(
    "acute" "chronic" "severe" "mild" "moderate" "early-stage" "advanced" "recurrent" "refractory" "benign" "malignant" "progressive" "stable" "complicated" "uncomplicated"
    "primary" "secondary" "idiopathic" "acquired" "congenital" "hereditary" "sporadic" "familial" "endemic" "epidemic"
)

# 治疗方式变体
TREATMENT_VARIANTS=(
    "medical" "surgical" "interventional" "conservative" "aggressive" "palliative" "curative" "preventive" "emergency" "elective"
    "inpatient" "outpatient" "ambulatory" "home-based" "multidisciplinary" "personalized" "standardized" "evidence-based"
)

# 专科领域
SPECIALTIES=(
    "cardiology" "oncology" "neurology" "gastroenterology" "pulmonology" "endocrinology" "rheumatology" "nephrology"
    "dermatology" "ophthalmology" "otolaryngology" "urology" "orthopedics" "psychiatry" "pediatrics" "geriatrics"
)

echo "开始生成和摄取大量文档..."

# 获取当前文档数
current_count=$(curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_count" | jq '.count')
echo "当前文档数量: $current_count"

# 目标文档数量
target_docs=1000
docs_to_add=$((target_docs - current_count))

if [ $docs_to_add -le 0 ]; then
    echo "索引中已有足够的文档 ($current_count >= $target_docs)"
    exit 0
fi

echo "需要添加 $docs_to_add 个文档"

# 批量摄取文档
batch_size=50
doc_id=$((current_count + 1))

for batch in $(seq 1 $((docs_to_add / batch_size + 1))); do
    echo "处理批次 $batch..."
    
    # 创建批量请求
    bulk_data=""
    
    for i in $(seq 1 $batch_size); do
        if [ $doc_id -gt $target_docs ]; then
            break
        fi
        
        # 随机选择模板和变体
        template_idx=$((RANDOM % ${#DOCUMENT_TEMPLATES[@]}))
        disease_idx=$((RANDOM % ${#DISEASE_VARIANTS[@]}))
        treatment_idx=$((RANDOM % ${#TREATMENT_VARIANTS[@]}))
        specialty_idx=$((RANDOM % ${#SPECIALTIES[@]}))
        
        template="${DOCUMENT_TEMPLATES[$template_idx]}"
        disease="${DISEASE_VARIANTS[$disease_idx]}"
        treatment="${TREATMENT_VARIANTS[$treatment_idx]}"
        specialty="${SPECIALTIES[$specialty_idx]}"
        
        # 生成变体文档
        doc_text="$treatment $disease conditions in $specialty require specialized management approaches. $template Additional research in $specialty continues to improve patient outcomes through innovative $treatment strategies."
        
        # 添加到批量请求
        bulk_data="$bulk_data{\"index\":{\"_index\":\"$INDEX_NAME\",\"_id\":\"$doc_id\"}}\n"
        bulk_data="$bulk_data{\"text\":\"$doc_text\"}\n"
        
        doc_id=$((doc_id + 1))
    done
    
    # 执行批量摄取
    if [ ! -z "$bulk_data" ]; then
        echo -e "$bulk_data" | curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_bulk" \
            -H 'Content-Type: application/json' --data-binary @- > /dev/null
        
        echo "  已添加最多 $batch_size 个文档 (总计: $((doc_id - 1)))"
    fi
    
    # 避免过载
    sleep 0.5
done

# 刷新索引
echo "刷新索引..."
curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_refresh" > /dev/null

# 验证最终文档数
final_count=$(curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/${INDEX_NAME}/_count" | jq '.count')
echo ""
echo "=== 摄取完成 ==="
echo "最终文档数量: $final_count"
echo "增加的文档数: $((final_count - current_count))"