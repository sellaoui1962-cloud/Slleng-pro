import csv
import re
import time
import random
from googletrans import Translator

# إعداد المترجم مع انتحال بصمة متصفح كروم
translator = Translator()

input_file = 'translation_sheet.csv'
output_file = 'translation_sheet_final.csv'

def protect_and_translate(text, target_lang):
    if not text or str(text).strip() == "":
        return ""
    
    text = str(text)
    # استخراج المتغيرات مثل ${e} و $name
    placeholders = re.findall(r'\$\{[^}]+\}|\$\w+', text)
    for i, p in enumerate(placeholders):
        text = text.replace(p, f"__VAR_{i}__")
    
    try:
        # الترجمة
        result = translator.translate(text, dest=target_lang, src='zh-CN')
        translated_text = result.text
        
        # التحقق من أن النتيجة ليست صينية (علامة على فشل الترجمة)
        if re.search(r'[\u4e00-\u9fff]', translated_text):
            raise Exception("الترجمة أعادت نصاً صينياً")
            
        # إعادة المتغيرات لمكانها
        for i, p in enumerate(placeholders):
            translated_text = translated_text.replace(f"__VAR_{i}__", p)
            
        # تأخير عشوائي لتجنب الحظر
        time.sleep(random.uniform(0.5, 1.5)) 
        return translated_text
        
    except Exception as e:
        print(f"⚠️ فشل ترجمة السطر: {e}")
        return text # إعادة النص الأصلي في حال الفشل (سيتم اكتشافه لاحقاً)

print("🚀 بدء الترجمة الآمنة... قد يستغرق الأمر وقتاً طويلاً.")

with open(input_file, mode='r', encoding='utf-8-sig') as infile, \
     open(output_file, mode='w', encoding='utf-8-sig', newline='') as outfile:
    
    reader = csv.reader(infile)
    writer = csv.writer(outfile)
    
    headers = next(reader)
    writer.writerow(headers)
    
    zh_idx = headers.index('zh')
    en_idx = headers.index('en')
    ar_idx = headers.index('ar')
    fr_idx = headers.index('fr')
    
    count = 0
    for row in reader:
        if len(row) > zh_idx:
            zh_text = row[zh_idx]
            
            # ترجمة فقط إذا كان النص غير فارغ والعمود العربي فارغ
            if zh_text.strip() != "" and row[ar_idx].strip() == "":
                print(f"جاري ترجمة السطر {count}...")
                row[en_idx] = protect_and_translate(zh_text, 'en')
                row[ar_idx] = protect_and_translate(zh_text, 'ar')
                row[fr_idx] = protect_and_translate(zh_text, 'fr')
            
            count += 1
            # حفظ النتائج كل 50 سطراً لتجنب فقدان التقدم
            if count % 50 == 0:
                outfile.flush()
                print(f"✅ تمت معالجة {count} سطر...")
                
        writer.writerow(row)

print("🎉 اكتملت العملية! تحقق من الملف الجديد.")
