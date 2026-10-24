# تثبيت مرحّل Zyrln على VPS Ubuntu واستخدامه على Android

يحتوي هذا المستودع على مثبت Bash مستقل ودليل عربي لإعداد **مرحّل خروج Zyrln** على VPS يعمل بـUbuntu، ثم ربطه بتطبيق Android عبر Google Apps Script.

> **تنبيه:** المثبت يجهّز جزء الـVPS فقط. لا ينشر Google Apps Script نيابةً عنك، ولا يثبت APK على الهاتف؛ يلزم إكمال هذين الجزأين من حساب Google وهاتف Android الخاصين بك.

## الملفات

- [`install-zyrln-relay.sh`](install-zyrln-relay.sh): تنزيل ثنائية Zyrln الرسمية وإعداد الخدمة واختبارها، ثم طباعة ثوابت Apps Script النهائية.
- [`README.md`](README.md): خطوات التثبيت والتكوين والصيانة واستكشاف الأعطال.

## مسار الاتصال

```text
Android Zyrln VPN
  │ عنوان Apps Script + AUTH_KEY
  ▼
Google Apps Script Web App
  │ EXIT_RELAY_URL + EXIT_RELAY_KEY
  ▼
Zyrln relay على VPS Ubuntu، TCP 8787
  ▼
الموقع المقصود
```

لا تدخل عنوان الـVPS في حقل URL داخل تطبيق Android. التطبيق يستخدم عنوان Web App الخاص بـGoogle والمنتهي بـ`/exec` ومفتاح التطبيق فقط. مفتاح الخروج يُستخدم بين Apps Script والخادم.[1]

## المتطلبات

- VPS بعنوان IP عام، يعمل بنظام Ubuntu وsystemd، ومعمارية `amd64` أو `arm64`.
- صلاحية `root` أو حساب يملك `sudo`.
- اتصال صادر بالإنترنت لتنزيل ملف GitHub الرسمي والوصول إلى المواقع المطلوبة.
- سماح **Inbound TCP 8787** في جدار مزوّد VPS. إذا كان UFW مفعّلًا مسبقًا، يضيف المثبت قاعدة لهذا المنفذ. لا يفعّل UFW تلقائيًا حتى لا يقطع وصول SSH.
- حساب Google يستطيع نشر Apps Script Web App بصلاحية `Anyone`، وهاتف Android لتثبيت التطبيق.

## 1. تنزيل السكربت وتشغيله

نزّل `install-zyrln-relay.sh` من المستودع الخاص بعد تسجيل الدخول إلى GitHub، ثم انقله إلى الـVPS عبر SCP أو أداة نقل ملفات موثوقة. مثال من جهازك:

```bash
scp ./install-zyrln-relay.sh ubuntu@YOUR_VPS_IP:~/install-zyrln-relay.sh
ssh ubuntu@YOUR_VPS_IP
```

على الخادم:

```bash
chmod 700 ~/install-zyrln-relay.sh
sudo bash ~/install-zyrln-relay.sh
```

### ما الذي يفعله المثبت؟

المثبت مثبت على إصدار المشروع المستقر **v2.0** لضمان توافق المرحّل مع خطوات Apps Script وAndroid في هذا الدليل. يتحقق من Ubuntu وsystemd ومعمارية الجهاز، ثم ينزّل حزمة VPS الرسمية عبر HTTPS، ويستخرج الملف التنفيذي المناسب، وينشئ مستخدم خدمة محدود الصلاحيات باسم `zyrln`، ويشغّل الخدمة عبر systemd لتبدأ تلقائيًا بعد إعادة تشغيل الخادم.

يطالبك بإدخال **مفتاح الخروج** `EXIT_RELAY_KEY` و**مفتاح التطبيق** `AUTH_KEY` بشكل مخفي. إذا تركت قيمة أحدهما فارغة، ينشئ المثبت مفتاحًا عشوائيًا قويًا. كما يحاول اكتشاف IPv4 العام للخادم تلقائيًا. إذا تعذّر ذلك، يطلب عنوان IP العام أو اسم DNS؛ ويمكن تحديده مسبقًا بالمتغير `ZYRLN_PUBLIC_HOST`.

بعد التثبيت، يطبع المثبت كتلة الثوابت الأربع كاملة وجاهزة للنسخ إلى أعلى ملف `Code.gs`:

```js
const AUTH_KEY = "المفتاح_الذي_أدخلته_أو_ولّده_المثبت";
const EXIT_RELAY_URL = "http://عنوان_VPS_العام:8787/relay";
const EXIT_TUNNEL_URL = "http://عنوان_VPS_العام:8787/tunnel";
const EXIT_RELAY_KEY = "مفتاح_الخروج_الذي_أدخلته_أو_ولّده_المثبت";
```

انسخ القيم الحقيقية التي يطبعها الطرفية؛ المثال أعلاه للتوضيح فقط. يخزن المثبت مفتاح الخروج في `/etc/zyrln-relay.env` بصلاحيات `0640`، ويحفظ مفتاح التطبيق منفصلًا في `/etc/zyrln-app-key` بصلاحيات `0600` للـroot فقط. لا يحتاج برنامج المرحّل إلى مفتاح التطبيق. **لا تضف القيم المطبوعة إلى GitHub أو إلى ملف عام.**

إذا كان لديك Apps Script قائم وتريد إبقاء `AUTH_KEY` المستخدم حاليًا، أدخله عند مطالبة المثبت بدل ترك الحقل فارغًا. وإذا تركت المطالبة فارغة، سينشئ مفتاحًا جديدًا؛ يجب حينها تحديث Apps Script وإعداد Android بالقيم الجديدة.

### إعادة التشغيل أو تحديث المثبت

يمكنك تشغيل السكربت نفسه مرة أخرى لتحديث ثنائية الإصدار المثبت أو إعادة إنشاء وحدة الخدمة. إذا تركت مطالبة كل مفتاح فارغة، يقرأ المثبت المفتاح المحفوظ ويعيد طباعة نفس الثوابت. استرجع القيم يدويًا عند الحاجة بصلاحيات root، ولا تشارك ناتجها:

```bash
sudo grep '^ZYRLN_RELAY_KEY=' /etc/zyrln-relay.env
sudo cat /etc/zyrln-app-key
```

لأتمتة التثبيت يمكن تمرير `ZYRLN_APP_KEY` و`ZYRLN_RELAY_KEY` و`ZYRLN_RELAY_PORT` و`ZYRLN_PUBLIC_HOST` كمتغيرات بيئة. لا تضع سرًا في سطر أمر إذا كان ذلك سيحفظه بسجل الطرفية أو يعرضه في قائمة العمليات؛ الإدخال المخفي هو الخيار المناسب عادةً.

## 2. افتح المنفذ في لوحة مزوّد VPS

من لوحة مزوّد الخادم، أضف قاعدة **Inbound TCP 8787**. جدار الشبكة لدى المزوّد مستقل عن UFW داخل Ubuntu. لا تفعّل UFW عن بُعد قبل السماح بمنفذ SSH الصحيح حتى لا تفقد الوصول إلى الخادم.[2]

تحقق من UFW:

```bash
sudo ufw status
```

إذا كان فعالًا ولم يضف المثبت القاعدة:

```bash
sudo ufw allow 8787/tcp
```

فتح المنفذ في لوحة المزوّد مطلوب حتى لو كانت قاعدة UFW موجودة.

## 3. تحقق من الخدمة

على VPS:

```bash
sudo systemctl status zyrln-relay --no-pager
curl -i http://127.0.0.1:8787/healthz
```

ومن جهاز آخر على الإنترنت:

```bash
curl -i http://YOUR_VPS_IP:8787/healthz
```

الاستجابة المتوقعة `HTTP 200` ومتن النص `ok`. هذا يختبر وصول الشبكة إلى المرحّل فقط، ولا يثبت أن Google Apps Script أو Android أُعدّا.[1]

أوامر إدارة وتشخيص:

```bash
sudo systemctl restart zyrln-relay
sudo systemctl stop zyrln-relay
sudo systemctl start zyrln-relay
sudo journalctl -u zyrln-relay -n 100 --no-pager
sudo ss -lntp | grep ':8787'
```

## 4. إنشاء Google Apps Script

1. افتح [script.google.com](https://script.google.com) وأنشئ مشروعًا جديدًا.
2. انسخ محتوى [`Code.gs` الرسمي المطابق للإصدار v2.0](https://github.com/ajavadinezhad/zyrln/blob/v2.0/relay/deploy/apps-script/Code.gs) كاملًا إلى محرر المشروع.
3. الصق كتلة الثوابت الأربع التي طبعها المثبت في بداية `Code.gs` بدل القيم النموذجية. تأكد من بقاء بقية الكود كما هو.
4. اختر **Deploy → New deployment → Web app**.
5. اختر **Execute as: Me** و**Who has access: Anyone**، ثم **Deploy** ووافق على أذونات Google.
6. انسخ رابط النشر الذي ينتهي بـ`/exec`.

إذا عدّلت `Code.gs` بعد النشر، اذهب إلى **Deploy → Manage deployments → Edit → New version → Deploy**. حفظ الملف وحده لا يحدّث النسخة المنشورة. إذا منع حساب Google Workspace خيار `Anyone`، تحقق من سياسة المؤسسة أو استخدم حسابًا يسمح بهذا الإعداد.[3]

## 5. إعداد Android

1. نزّل APK الرسمي من صفحة [إصدار v2.0](https://github.com/ajavadinezhad/zyrln/releases/tag/v2.0)، واختر الملف المنتهي بـ`-android.apk`.
2. ثبّت التطبيق. إذا طلب Android السماح بالتثبيت من هذا المصدر، اسمح به للمتصفح أو مدير الملفات الذي فتح APK.
3. أضف ملف اتصال. أدخل رابط Google Apps Script المنتهي بـ`/exec` في خانة URL، واستخدم قيمة `AUTH_KEY` المطبوعة في خانة key.
4. اضغط **Connect** ووافق على طلب Android لإنشاء اتصال VPN.
5. افتح موقعًا فعليًا للاختبار. نجاح Ping وحده لا يكفي. لتغيير **Split tunnel** افصل الاتصال أولًا.[4]

شكل إعداد التطبيق يكون مثل:

```json
{"url":"https://script.google.com/macros/s/DEPLOYMENT_ID/exec","key":"قيمة_AUTH_KEY_المطبوعة"}
```

لا تستخدم عنوان VPS أو مفتاح الخروج في تطبيق Android. تعامل مع JSON على أنه سر؛ من يحصل عليه قد يستخدم relay وحصة Apps Script.[1] [4]

## 6. قائمة فحص إذا لم يعمل

1. `systemctl status zyrln-relay` يظهر `active (running)`.
2. `/healthz` يعمل محليًا ومن جهاز خارجي.
3. `8787/TCP` مسموح في جدار مزود VPS وUFW إذا كان فعالًا.
4. عناوين `EXIT_RELAY_URL` و`EXIT_TUNNEL_URL` تستخدم المضيف والمنفذ والمسارين الصحيحين.
5. `EXIT_RELAY_KEY` في Apps Script يطابق مفتاح الخروج المحفوظ على الخادم.
6. `AUTH_KEY` في Apps Script يطابق المفتاح الذي تستخدمه في Android.
7. رابط Android هو عنوان Web App المنشور والمنتهي بـ`/exec`، وليس `/dev` أو عنوان VPS.
8. آخر تعديل على Apps Script منشور كـ**New version**.
9. أوقف أي VPN آخر مؤقتًا إذا كان يتعارض مع Zyrln.

## 7. الأمان والقيود

- لا تحفظ المفاتيح أو إعداد الاتصال في هذا المستودع، حتى لو كان Private.
- العناوين الافتراضية تستخدم `http://` بين Google Apps Script والـVPS؛ هذا الجزء ليس مشفرًا بواسطة TLS افتراضيًا. لحمايته، جهّز Reverse Proxy وشهادة TLS أولًا، وبعدها غيّر العنوانين إلى HTTPS. لا تغيّر الروابط قبل إعداد TLS والتحقق منه.
- يعمل المرحّل تحت مستخدم نظامي محدود الصلاحيات. لا تشارك المفاتيح، ودوّرها إذا اشتبهت بتسريبها.
- نفق Android في v2.0 يمرر TCP فقط، ولا يمرر UDP؛ لذلك قد لا تعمل المكالمات أو بعض وظائف التطبيقات.[1]
- استجابة `ok` من `/healthz` لا تؤكد نجاح السلسلة كاملة.

## تدوير المفاتيح

للتغيير اليدوي لمفتاح الخروج، عدّل الملف:

```bash
sudoedit /etc/zyrln-relay.env
sudo systemctl restart zyrln-relay
```

ثم حدّث `EXIT_RELAY_KEY` في Apps Script وانشر **New version**. مفتاح التطبيق محفوظ منفصلًا في `/etc/zyrln-app-key`. إذا غيّرته يدويًا، استخدم مفتاحًا جديدًا بطول 32 محرفًا على الأقل، ثم حدّث `AUTH_KEY` في Apps Script وإعداد Android.

## استكشاف الأخطاء

**فشل تنزيل حزمة GitHub:** افحص DNS والإنترنت الصادر من الخادم، ثم أعد التشغيل. المثبت ينزّل حزمة VPS الرسمية ويستخرج منها الملف التنفيذي، ولا ينفّذ سكربت shell عشوائيًا عن بُعد.

**فشل `healthz` المحلي:** افحص `journalctl -u zyrln-relay -n 100 --no-pager` وملف `/etc/zyrln-relay.env` وصلاحيات الخدمة.

**يعمل محليًا ولا يعمل من الخارج:** افحص جدار مزود VPS أولًا، ثم UFW، ثم عنوان IP العام والمنفذ `8787/TCP`.

**Apps Script يعرض Unauthorized:** تحقق من تطابق `AUTH_KEY` مع مفتاح Android، ومن تطابق `EXIT_RELAY_KEY` مع مفتاح الخروج على VPS، ثم انشر إصدارًا جديدًا.

**بعض التطبيقات أو المكالمات لا تعمل:** تذكر أن نفق Android في هذا الإصدار TCP فقط، وقد لا يدعم وظائف UDP.

## مصادر رسمية

[1]: https://github.com/ajavadinezhad/zyrln "شرح بنية Zyrln وإعداد الـrelay"
[2]: https://ubuntu.com/server/docs/how-to/security/firewalls "توثيق Ubuntu لجدار UFW"
[3]: https://developers.google.com/apps-script/guides/web "توثيق Google Apps Script Web Apps"
[4]: https://github.com/ajavadinezhad/zyrln/blob/main/docs/fa/guide.md "دليل استخدام Zyrln على Android"
