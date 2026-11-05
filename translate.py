import csv
import re
import time
from deep_translator import GoogleTranslator

# أسماء الملفات
input_file = 'translation_sheet.csv'
output_file = 'translation_sheet_translated.csv'

# دالة لحماية المتغيرات البرمجية (مثل $e و ${name})
def protect_and_translate(text, target_lang):
    if not text or str(text).strip() == "":
        return ""
    
    text = str(text)
    # استخراج المتغيرات وحفظها مؤقتاً
    placeholders = re.findall(r'\$\{[^}]+\}|\$\w+', text)
    for i, p in enumerate(placeholders):
        text = text.replace(p, f"PH{i}")
    
    try:
        # الترجمة إلى اللغة المطلوبة
        translated = GoogleTranslator(source='zh-CN', target=target_lang).translate(text)
        # إعادة المتغيرات إلى مكانها
        for i, p in enumerate(placeholders):
            translated = translated.replace(f"PH{i}", p)
        time.sleep(0.3) # تأخير بسيط لتجنب حظر جوجل
        return translated
    except Exception as e:
        return text 

print("بدء الترجمة... لا تغلق التطبيق حتى ينتهي.")

# فتح الملف الأصلي وإنشاء ملف جديد للترجمة باستخدام csv العادية
with open(input_file, mode='r', encoding='utf-8-sig') as infile, \
     open(output_file, mode='w', encoding='utf-8-sig', newline='') as outfile:
    
    reader = csv.reader(infile)
    writer = csv.writer(outfile)
    
    headers = next(reader)
    writer.writerow(headers)
    
    # معرفة أرقام الأعمدة
    zh_idx = headers.index('zh')
    en_idx = headers.index('en')
    ar_idx = headers.index('ar')
    fr_idx = headers.index('fr')
    
    count = 0
    for row in reader:
        if len(row) > zh_idx:
            zh_text = row[zh_idx]
            
            # ترجمة النص فقط إذا كان العمود العربي فارغاً
            if zh_text.strip() != "":
                if row[ar_idx].strip() == "":
                    row[en_idx] = protect_and_translate(zh_text, 'en')
                    row[ar_idx] = protect_and_translate(zh_text, 'ar')
                    row[fr_idx] = protect_and_translate(zh_text, 'fr')
            
            count += 1
            if count % 50 == 0:
                print(f"تمت ترجمة {count} سطر...")
                
        writer.writerow(row)

print("✅ اكتملت الترجمة بنجاح!")
print(f"الملف الجديد هو: {output_file}")
