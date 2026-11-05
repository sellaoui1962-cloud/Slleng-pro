import csv
import re
import time
import random
from deep_translator import GoogleTranslator

input_file = 'translation_sheet.csv'
output_file = 'translation_sheet_ui.csv'

def protect_and_translate(text, target_lang):
    if not text or str(text).strip() == "": return ""
    text = str(text)
    placeholders = re.findall(r'\$\{[^}]+\}|\$\w+', text)
    for i, p in enumerate(placeholders):
        text = text.replace(p, f"__VAR_{i}__")
    try:
        translated = GoogleTranslator(source='zh-CN', target=target_lang).translate(text)
        if re.search(r'[\u4e00-\u9fff]', translated):
            return text # فشل الترجمة
        for i, p in enumerate(placeholders):
            translated = translated.replace(f"__VAR_{i}__", p)
        time.sleep(random.uniform(0.5, 1.2)) # تأخير لتجنب الحظر
        return translated
    except Exception:
        return text

print("🚀 بدء فلترة وترجمة واجهات المستخدم فقط...")
translated_count = 0

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
    cat_idx = headers.index('category')
    used_idx = headers.index('used_in')
    
    for row in reader:
        if len(row) > used_idx:
            category = row[cat_idx]
            used_in = row[used_idx]
            
            # شرط الفلترة: تجاهل model_prompt، وتجاهل الخدمات
            is_ui = (category == 'ui' or category == '') and ('screens/' in used_in or 'widgets/' in used_in or 'main.dart' in used_in)
            
            if is_ui and row[zh_idx].strip() != "" and row[ar_idx].strip() == "":
                zh_text = row[zh_idx]
                row[en_idx] = protect_and_translate(zh_text, 'en')
                row[ar_idx] = protect_and_translate(zh_text, 'ar')
                row[fr_idx] = protect_and_translate(zh_text, 'fr')
                translated_count += 1
                if translated_count % 10 == 0:
                    print(f"تمت ترجمة {translated_count} عنصر واجهة...")
            
            writer.writerow(row)

print(f"🎉 اكتمل! تمت ترجمة {translated_count} عنصر واجهة فقط، وتم تجاهل الباقي.")
