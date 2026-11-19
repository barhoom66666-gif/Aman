# النشر على GitHub وبناء APK خطوة بخطوة

هذا الدليل يأخذك من مشروع محلي إلى ملف APK جاهز للتثبيت، بدون الحاجة إلى
تثبيت Flutter أو Android Studio على جهازك.

المدة المتوقعة: 10–15 دقيقة (أول بناء فقط، ثم 5–8 دقائق لكل بناء جديد).

---

## 1) أنشئ مستودعًا على GitHub

1. افتح <https://github.com/new>.
2. الاسم: `aman` (أو أي اسم).
3. اختر **Private** إن أردت إبقاء الكود خاصًا، أو **Public**.
4. **لا تضف** README أو .gitignore أو License (المشروع يحتويها بالفعل).
5. اضغط **Create repository** وانسخ رابط المستودع.

## 2) ارفع المشروع من جهازك

افتح Terminal داخل مجلد المشروع `aman` (المجلد الذي يحتوي `app/` و`server/`):

```bash
git init -b main
git config user.name "اسمك"
git config user.email "بريدك@example.com"

git add .
git commit -m "Aman: النسخة الأولى"

git remote add origin https://github.com/USERNAME/aman.git
git push -u origin main
```

- استبدل `USERNAME` باسم المستخدم لديك.
- عند طلب كلمة المرور استخدم **Personal Access Token** (GitHub → Settings →
  Developer settings → Tokens) وليس كلمة مرور الحساب.
- بديل أسهل بدون أوامر: استخدم **GitHub Desktop** → Add local repository → Publish.

## 3) شغّل البناء

البناء يعمل تلقائيًا عند كل `push` إلى `main`. للمرة الأولى:

- افتح المستودع → تبويب **Actions**.
- اختر **Android CI** → **Run workflow**.
- اترك `api_url` فارغًا (سيُستخدم `http://10.0.2.2:8080` للمحاكي)، أو أدخل
  عنوان خادمك مثل `http://192.168.1.20:8080`.
- اضغط **Run workflow**.

سيتم أولًا تشغيل اختبارات الخادم الأربعة، ثم تحليل كود Flutter، ثم بناء الـ APK.
إن فشلت الاختبارات لن يُبنى الـ APK.

## 4) نزّل APK

بعد انتهاء التشغيل الأخضر:

- افتح صفحة التشغيل → قسم **Artifacts** → `aman-apk.zip`.
- فك الضغط → `app-release.apk` (حجمه نحو 20–25 ميجابايت).
- الملف محفوظ في GitHub لمدة 30 يومًا.

## 5) ثبّته على الهاتف

1. انقل `app-release.apk` إلى الهاتف (كابل، Google Drive، أو Telegram لنفسك).
2. عند فتح الملف سيطلب أندرويد السماح بالتثبيت من هذا المصدر → اسمح.
3. ثبّت وافتح «Aman».
4. عند أول تشغيل اضغط سطر **«الخادم: …»** وأدخل عنوان خادمك:
   - من محاكي أندرويد على نفس الكمبيوتر: `http://10.0.2.2:8080`
   - من هاتف على نفس شبكة الواي فاي: `http://IP-الكمبيوتر:8080`
     (مثال `http://192.168.1.20:8080`، واعرف IP بأمر `ip addr` أو `ipconfig`).
5. أنشئ حسابًا جديدًا وابدأ محادثة.

> لا تحتاج إلى إعادة بناء التطبيق لتغيير الخادم؛ يمكن تغييره من الإعدادات في أي وقت.

## 6) اجعل عنوان الخادم افتراضيًا (اختياري)

المستودع → **Settings** → **Secrets and variables** → **Actions** →
تبويب **Variables** → **New repository variable**:

- الاسم: `AMAN_API`
- القيمة: `http://192.168.1.20:8080`

بعدها كل بناء جديد سيضمّن هذا العنوان، ويمكن للمستخدم تغييره من داخل التطبيق.

## 7) التوقيع للإنتاج (لاحقًا، عند النشر الحقيقي)

الـ APK الحالي موقّع بمفتاح **debug** — مناسب للتجربة، لكنه غير صالح للنشر على
Google Play أو للتحديث فوق نسخة موقّعة بمفتاح آخر.

لإنشاء مفتاح إنتاج:

```bash
keytool -genkey -v -keystore aman-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias aman
```

أنشئ `app/android/key.properties` (مستثنى من git):

```properties
storePassword=كلمة-سر-المخزن
keyPassword=كلمة-سر-المفتاح
keyAlias=aman
storeFile=/المسار/الكامل/aman-release.jks
```

ثم عدّل `app/android/app/build.gradle.kts`:

```kotlin
import java.io.FileInputStream
import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // ... الموجود حاليًا ...

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}
```

للـ CI: ارفع المفتاح كـ secret (Base64) وأضف خطوة فكّ ترميز قبل البناء،
أو ابنِ الـ APK الموقّع محليًا على جهازك.

## 8) حل المشكلات الشائعة

| المشكلة | الحل |
|---|---|
| `npm ci` يفشل | تأكد أن `server/package-lock.json` مرفوع مع المشروع |
| فشل `flutter pub get` | تحقق من إصدار Flutter في الـ Workflow (3.50.0) |
| APK لا يتصل بالخادم | الهاتف والخادم على نفس الشبكة؟ استخدم IP الكمبيوتر لا `127.0.0.1` |
| شاشة بيضاء/خطأ اتصال | جرّب فتح `http://IP:8080/health` من متصفح الهاتف |
| التثبيت مرفوض | احذف نسخة سابقة موقّعة بمفتاح مختلف ثم أعد التثبيت |
| Build بطيء أول مرة | طبيعي: تنزيل Flutter وGradle (5–10 دقائق) |

## 9) بديل: البناء محليًا

إن كان لديك Flutter مثبتًا:

```bash
cd app
flutter pub get
flutter build apk --release --dart-define=AMAN_API=http://192.168.1.20:8080
# الناتج: build/app/outputs/flutter-apk/app-release.apk
```

## 10) iOS لاحقًا

يحتاج بناء iOS إلى جهاز Mac (أو runner macOS في GitHub Actions) لأن Apple
تشترط Xcode. الكود نفسه جاهز: راجع قسم «إضافة iOS لاحقًا» في `README.md`.
