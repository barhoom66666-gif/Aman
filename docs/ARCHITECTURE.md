# المعمارية

## نظرة عامة

```
┌────────────┐    HTTPS/WS     ┌──────────────────┐
│ Flutter    │ ◀─────────────▶ │ Node.js          │
│ (جهاز)     │                 │ Express + ws     │
│            │                 │                  │
│ مفاتيح خاصة│                 │ SQLite           │
│ تشفير/فك   │                 │ media/ (بايتات   │
│ SQLite     │                 │  مشفّرة فقط)     │
└────────────┘                 └──────────────────┘
```

الخادم لا يملك أي مفتاح خاص، ولا يستطيع فك أي رسالة. وظيفته: المصادقة،
تخزين/توزيع المغلفات، توزيع مفاتيح المجموعات المشفّرة، وبثّ الأحداث فوريًا.

## الهوية والمفاتيح

- عند أول تشغيل يولّد التطبيق بذرة عشوائية 32 بايت ويخزّنها في
  `flutter_secure_storage` (Android Keystore / iOS Keychain).
- منها يُشتق زوج X25519. يُرسَل **المفتاح العام** فقط عند التسجيل.
- لا يوجد استيراد/تصدير للمفتاح في هذه النسخة؛ إعادة التثبيت = هوية جديدة.

## مخطط الرسالة الفردية

لكل رسالة مفتاح مؤقت جديد (ephemeral):

```
sender:
  (esk, epk) ← X25519.newKeyPair()
  shared     ← ECDH(esk, recipient_identity_pub)
  key        ← HKDF-SHA256(shared, salt=16B, info="najwa/v1/pairwise", 32B)
  ct         ← AES-256-GCM(key, nonce=12B, aad="najwa/v1|chatId|senderId|recipientId")
  envelope   = {v:1, alg:"x25519-aesgcm", epk, salt, nonce, ct||tag}

receiver:
  shared ← ECDH(identity_priv, epk)   ⇒ نفس المفتاح
```

الرسالة الصريحة (payload) هي JSON:

```json
{"t":"text","body":"..."}
{"t":"media","id":"f…","key":"…","nonce":"…","name":"…","mime":"image/jpeg","size":1234}
```

## المجموعات (Sender Keys)

لكل مجموعة مفتاح متماثل عشوائي 32 بايت لكل «جيل» (epoch):

1. منشئ المجموعة (أو أي عضو) يولّد المفتاح.
2. يشفّره لكل عضو على حدة بمخطط ECDH نفسه مع
   `info="najwa/v1/groupkey"` و`aad` يحتوي معرّف المستلم.
3. يرفع المغلفات إلى `POST /api/chats/:id/keys`.
4. كل عضو يجلب مغلفه من `GET /api/chats/:id/keys/:epoch` ويفكّه ويخزّنه محليًا
   **مشفّرًا** بمفتاح جهاز.
5. رسائل المجموعة تُشفّر مرة واحدة:
   `AES-256-GCM(groupKey, aad="najwa/v1/group|chatId|epoch|senderId")`.

عند تغيّر الأعضاء (إضافة/إزالة/مغادرة) يزيد `epoch`، ويُعاد توزيع مفتاح جديد،
وتُرفض الرسائل بالجيل القديم (`409 epoch_mismatch`) فيعيد العميل التشفير.

## الوسائط

1. العميل يشفّر الملف بمفتاح عشوائي AES-GCM.
2. يرفع البايتات المشفّرة إلى `POST /api/media?chatId=…`.
3. يرسل داخل الرسالة المشفّرة: معرّف الملف + المفتاح + nonce.
4. المستلم ينزّل ثم يفكّ محليًا، ويحفظ نسخة في مجلد التطبيق.

الخادم يتحقق من العضوية قبل الرفع والتنزيل، ويرفض الملفات الأكبر من
`MAX_MEDIA_BYTES` (25MB افتراضيًا).

## واجهة REST

| الطريقة | المسار | الوظيفة |
|---|---|---|
| POST | `/api/auth/register` | إنشاء حساب + مفتاح عام |
| POST | `/api/auth/login` | إصدار رمز جلسة |
| POST | `/api/auth/logout` | إبطال الرمز |
| GET | `/api/me` | بيانات الحساب |
| PATCH | `/api/me` | تعديل الاسم |
| POST | `/api/me/identity` | تحديث مفتاح هوية الجهاز |
| GET | `/api/users?q=` | بحث بالاسم/المستخدم |
| GET | `/api/users/:username/key` | مفتاح عام + prekey اختياري |
| POST | `/api/prekeys` | رفع مفاتيح مسبقة |
| GET | `/api/chats` | قائمة المحادثات + غير المقروء |
| POST | `/api/chats/direct` | فتح/إنشاء محادثة فردية |
| POST | `/api/chats/group` | إنشاء مجموعة |
| POST | `/api/chats/:id/members` | إضافة أعضاء (ترفع epoch) |
| DELETE | `/api/chats/:id/members/:userId` | إزالة عضو (المنشئ) |
| POST | `/api/chats/:id/leave` | مغادرة |
| GET | `/api/chats/:id/messages` | صفحة رسائل (قبل/حد) |
| POST | `/api/chats/:id/messages` | إرسال مغلف (idempotent بـ clientId) |
| POST | `/api/chats/:id/read` | تعليم كمقروء |
| POST | `/api/chats/:id/keys` | نشر مغلفات مفتاح الجيل |
| GET | `/api/chats/:id/keys/:epoch` | مغلف مفتاحي |
| POST | `/api/media?chatId=` | رفع بايتات مشفّرة |
| GET | `/api/media/:id` | تنزيل بايتات مشفّرة |

## أحداث WebSocket (`/ws?token=…`)

من الخادم: `ready`, `presence`, `message`, `typing`, `read`, `chat`,
`chat_update`, `keys`, `removed`.
من العميل: `typing`, `ping`.

## قاعدة البيانات (SQLite)

`users`, `sessions` (تجزئة الرمز فقط), `prekeys`, `chats`, `chat_members`,
`messages` (مغلف + كاتب + وقت), `group_keys` (مغلف لكل مستلم/جيل), `media`.

قيود مفيدة: فهرس فريد `(chat_id, sender_id, client_id)` لمنع التكرار عند
إعادة المحاولة بعد انقطاع الشبكة.

## التطبيق (Flutter)

```
lib/
├── main.dart / app.dart        نقطة الدخول وحالة المصادقة
├── theme.dart / utils.dart     الهوية البصرية والتنسيقات العربية
├── models.dart                 User, Chat, Message, MediaInfo
├── core/
│   ├── config.dart             عنوان الخادم (dart-define أو إعدادات)
│   ├── crypto.dart             X25519/HKDF/AES-GCM + تخزين آمن
│   ├── api.dart                عميل REST
│   ├── db.dart                 SQLite محلي
│   └── session.dart            الحالة، المزامنة، WebSocket، إعادة المحاولة
├── screens/                    الترحيب، الدخول، المحادثات، الدردشة، الإعدادات
└── widgets/                    الصورة الرمزية، الشعار، عناصر مشتركة
```

`Session` هو `ChangeNotifier` واحد يملك المحادثات والرسائل، ويستخدمه الواجهة
عبر `provider`. كل رسالة واردة تُفكّ وتُخزَّن محليًا قبل إشعار الواجهة.
