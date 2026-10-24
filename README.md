# تثبيت مرحّل Zyrln على VPS Ubuntu واستخدامه على Android

هذا المستودع يحتوي على مثبت Bash مستقل ودليل عربي لإعداد **مرحّل خروج Zyrln** على VPS يعمل بـUbuntu، ثم ربطه بتطبيق Android عبر Google Apps Script.

> **تنبيه:** هذا المستودع يثبت جزء الـVPS فقط. لا ينشر Google Apps Script نيابةً عنك، ولا يثبت APK على الهاتف. هذان الجزآن يحتاجان حساب Google وجهاز Android خاصين بك.

## الملفات

- [`install-zyrln-relay.sh`](install-zyrln-relay.sh): مثبت واحد مستقل لتنزيل ثنائية Zyrln الرسمية، إعداد الخدمة، تشغيلها، واختبار الصحة.
- [`README.md`](README.md): خطوات التشغيل والتكوين والصيانة واستكشاف الأعطال.

## كيف تمر البيانات؟

```text
Android Zyrln VPN
  │ عنوان Apps Script + APP_KEY
  ▼
Google Apps Script Web App
  │ EXIT_RELAY_URL + EXIT_RELAY_KEY
  ▼
Zyrln relay على VPS Ubuntu، TCP 8787
  ▼
الموقع المقصود
```

لا تدخل عنوان الـVPS في حقل URL داخل تطبيق Android. التطبيق يستعمل عنوان Web App الخاص بـGoogle والمنتهي بـ`/exec`، ومفتاح التطبيق فقط. مفتاح الخروج يبقى في Apps Script وعلى الخادم.[1]

## المتطلبات

- VPS بعنوان IP عام ونظام Ubuntu يستخدم systemd. يدعم المثبت معماريتي `amd64` و`arm64`.
- صلاحية `root` أو حساب يملك `sudo`.
- اتصال إنترنت صادر من الخادم لتنزيل إصدار GitHub الرسمي والوصول إلى المواقع المطلوبة.
- سماح TCP الوارد على المنفذ `8787` في جدار مزوّد VPS. إذا كان UFW مفعّلًا أصلًا، يضيف المثبت قاعدة للمنفذ؛ لا يفعّل UFW تلقائيًا كي لا يقطع وصول SSH.
- حساب Google يستطيع إنشاء Apps Script ونشر Web App بصلاحية `Anyone`.
- جهاز Android لتثبيت ملف APK من إصدار المشروع الرسمي.

## 1. تنزيل السكربت وتشغيله

نزّل الملف `install-zyrln-relay.sh` من هذا المستودع على جهازك. لأن المستودع خاص، افتحه بعد تسجيل الدخول إلى GitHub واختر **Raw → Download**، أو نزّله من صفحة الملف عبر زر **Raw**. انقله إلى الـVPS باستخدام SCP أو أداة نقل ملفات موثوقة، ثم اتصل بالخادم عبر SSH.

مثال من الطرفية على جهازك، بعد استبدال المسار والعنوان:

```bash
scp ./install-zyrln-relay.sh ubuntu@YOUR_VPS_IP:~/install-zyrln-relay.sh
ssh ubuntu@YOUR_VPS_IP
```

على الخادم شغّل:

```bash
chmod 700 ~/install-zyrln-relay.sh
sudo bash ~/install-zyrln-relay.sh
```

يطلب المثبت مفتاح خروج مخفيًا. إذا تركته فارغًا، ينشئ مفتاحًا عشوائيًا من 256 بت ويعرضه مرة واحدة عند انتهاء التثبيت. احفظ المفتاح في مدير كلمات مرور. لا تضعه داخل هذا المستودع أو ملف عام.

المثبت مثبت افتراضيًا على إصدار المشروع المستقر **v2.0**. ويتحقق من Ubuntu وsystemd والمعمارية، ثم ينزّل حزمة VPS الرسمية عبر HTTPS، يستخرج الملف التنفيذي المناسب، ينشئ مستخدم خدمة نظاميًا باسم `zyrln`، ويحفظ الإعدادات في `/etc/zyrln-relay.env` بصلاحيات محدودة، وينشئ خدمة `systemd` تبدأ تلقائيًا بعد إعادة التشغيل، ثم يختبر `/healthz` محليًا.

### إعادة التشغيل أو تحديث التثبيت

يمكنك تشغيل السكربت نفسه مرة أخرى لتحديث ثنائية الإصدار المثبت أو إعادة إنشاء وحدة الخدمة. يحافظ على مفتاح الخروج الموجود في `/etc/zyrln-relay.env` إذا تركت مطالبة المفتاح فارغة. لاستخراج المفتاح الحالي عند الحاجة، استخدم حساب root أو sudo، ولا تنشر الناتج:

```bash
sudo grep '^ZYRLN_RELAY_KEY=' /etc/zyrln-relay.env
```

إذا غيّرت مفتاح الخروج في ملف البيئة يدويًا، أعد تشغيل الخدمة:

```bash
sudo systemctl restart zyrln-relay
```

لأغراض الإدارة الآلية، يمكن تمرير `ZYRLN_RELAY_KEY` و`ZYRLN_RELAY_PORT` كمتغيرات بيئة قبل تشغيل المثبت. انتبه إلى أن وضع سر في سطر أمر قد يحفظه في سجل الطرفية أو يظهره لفترة في قائمة العمليات. التفاعل المخفي هو الخيار الأنسب عادةً.

## 2. افتح المنفذ في لوحة مزوّد VPS

من لوحة مزوّد الخادم، أضف قاعدة **Inbound TCP 8787** إلى عنوان الخادم. جدار المزوّد مستقل عن UFW على Ubuntu. لا تفتح منفذ SSH إضافيًا أو تفعّل UFW من هذا الدليل دون إعداد قاعدة SSH الصحيحة أولًا.

تحقق من قواعد UFW:

```bash
sudo ufw status
```

إذا كان UFW فعالًا ولم يضف المثبت القاعدة، نفّذ:

```bash
sudo ufw allow 8787/tcp
```

المثبت لا يفعّل UFW من تلقاء نفسه لتجنب قفل جلسة الإدارة البعيدة. فتح المنفذ داخل لوحة المزوّد مطلوب حتى إذا كانت قاعدة UFW موجودة.[2]

## 3. تحقق من خدمة المرحّل

على VPS:

```bash
sudo systemctl status zyrln-relay --no-pager
curl -i http://127.0.0.1:8787/healthz
```

من جهاز آخر على الإنترنت:

```bash
curl -i http://YOUR_VPS_IP:8787/healthz
```

الاستجابة المتوقعة هي `HTTP 200` ومتن النص `ok`. هذا يختبر قابلية الوصول إلى الخدمة فقط؛ ولا يعني أن Google Apps Script أو Android أصبحا مُعدّين.[1]

أوامر مفيدة:

```bash
sudo systemctl restart zyrln-relay
sudo systemctl stop zyrln-relay
sudo systemctl start zyrln-relay
sudo journalctl -u zyrln-relay -n 100 --no-pager
sudo ss -lntp | grep ':8787'
```

## 4. إنشاء Google Apps Script

1. افتح [script.google.com](https://script.google.com) وأنشئ مشروعًا جديدًا.
2. من مصدر المشروع الرسمي للإصدار v2.0 انسخ محتوى [`Code.gs`](https://github.com/ajavadinezhad/zyrln/blob/v2.0/relay/deploy/apps-script/Code.gs) كاملًا والصقه في محرر المشروع.
3. أنشئ **مفتاح تطبيق** منفصلًا عن مفتاح الخروج. استخدم مفتاحًا عشوائيًا طويلًا واحفظه.
4. عدّل الثوابت الأربع في أول الملف. استبدل `APP_KEY` بمفتاح التطبيق، و`YOUR_VPS_IP` بعنوان VPS، و`EXIT_KEY` بمفتاح الخروج الذي عرضه المثبت:

```js
const AUTH_KEY = "APP_KEY_ضع_مفتاح_التطبيق_هنا";
const EXIT_RELAY_URL = "http://YOUR_VPS_IP:8787/relay";
const EXIT_TUNNEL_URL = "http://YOUR_VPS_IP:8787/tunnel";
const EXIT_RELAY_KEY = "EXIT_KEY_ضع_مفتاح_الخروج_هنا";
```

`AUTH_KEY` يساوي المفتاح الذي سيدخل في التطبيق. و`EXIT_RELAY_KEY` يساوي المفتاح المخزن على الـVPS. لا تبدّل بينهما، ولا تضع مفتاح الخروج في التطبيق.[1] [3]

5. اختر **Deploy → New deployment → Web app**.
6. عيّن **Execute as: Me** و**Who has access: Anyone**، ثم اضغط **Deploy** ووافق على أذونات Google.
7. احتفظ بعنوان النشر الذي ينتهي بـ`/exec`.

إذا غيّرت `Code.gs` بعد النشر، اذهب إلى **Deploy → Manage deployments → Edit → New version → Deploy**. حفظ الملف وحده لا يحدّث التطبيق المنشور. إذا كانت سياسات حساب Google Workspace تمنع خيار `Anyone`، لن يمكن إكمال هذا الأسلوب من الحساب قبل تعديل سياسة المؤسسة أو استخدام حساب مسموح.[3]

## 5. إعداد Android

1. نزّل APK الرسمي من صفحة [إصدار v2.0](https://github.com/ajavadinezhad/zyrln/releases/tag/v2.0)، واختر الملف الذي ينتهي بـ`-android.apk`.
2. ثبّت التطبيق على Android. إذا طلب النظام السماح بالتثبيت من هذا المصدر، اسمح به للمتصفح أو مدير الملفات الذي فتح APK، ثم أوقف الإذن لاحقًا إن رغبت.
3. أضف ملف اتصال في التطبيق. أدخل رابط Apps Script `/exec` في خانة URL ومفتاح التطبيق في خانة key. لا تستخدم عنوان الـVPS في هذه الخانة.
4. اضغط **Connect**، ووافق على طلب Android لإنشاء اتصال VPN.
5. افتح موقعًا فعليًا للاختبار. نجاح ping وحده ليس اختبارًا كافيًا. لفصل تطبيقات مختارة، افصل الاتصال أولًا ثم عدّل **Split tunnel**.[4]

يمكن تمثيل الإعداد بهذا JSON، مع استبدال القيم النموذجية:

```json
{"url":"https://script.google.com/macros/s/DEPLOYMENT_ID/exec","key":"APP_KEY_هنا"}
```

تعامل مع هذا الإعداد كمعلومة سرية؛ من يحصل عليه يستطيع استخدام Relay وحصة Apps Script المرتبطة به.[1] [4]

## 6. اختبار الإعداد كاملًا

اتبع التسلسل إذا لم يعمل الاتصال:

1. `systemctl status zyrln-relay` يظهر `active (running)`.
2. `/healthz` يعمل محليًا ومن جهاز خارجي.
3. المنفذ `8787/TCP` مسموح في جدار مزوّد VPS، وكذلك في UFW إن كان فعالًا.
4. `EXIT_RELAY_URL` و`EXIT_TUNNEL_URL` يشيران إلى IP الخادم والمنفذين والمسارين الصحيحين.
5. قيمة `EXIT_RELAY_KEY` تطابق `ZYRLN_RELAY_KEY` على الخادم.
6. قيمة `AUTH_KEY` تطابق Key في التطبيق.
7. رابط التطبيق هو رابط Google Apps Script المنشور والمنتهي بـ`/exec`، لا رابط `/dev` ولا عنوان VPS.
8. آخر تغيير في Apps Script منشور كـNew version.
9. أوقف تطبيق VPN آخر مؤقتًا إذا كان يتعارض مع Zyrln.

## 7. الأمان وحدود الاستخدام

- لا تضف المفاتيح أو روابط `/exec` السرية إلى GitHub، حتى لو كان المستودع خاصًا. المستودع في هذه النسخة يجب أن يحتوي على السكربت والشرح فقط، دون أسرار التشغيل.
- إعداد VPS الموضح هنا يستخدم `http://` من Apps Script إلى VPS. هذا يعني أن القناة بين Google والـVPS ليست مشفرة بـTLS افتراضيًا، رغم استخدام مفتاح الخروج. إذا أردت حماية هذا الجزء، جهّز نطاقًا وReverse Proxy وشهادة TLS أولًا، ثم حدّث عنواني relay وtunnel في Apps Script إلى HTTPS. لا تغيّر العناوين قبل تجهيز TLS واختباره.
- الخدمة تعمل تحت مستخدم نظام مخصص دون صلاحيات root. يبقى المنفذ متاحًا من الإنترنت حسب قواعد الشبكة. لا تشارك مفاتيحك، ودوّرها فور الاشتباه بتسريبها.
- نفق Android في v2.0 يمرر TCP فقط ولا يمرر UDP؛ لذلك قد لا تعمل مكالمات WhatsApp وبعض وظائف التطبيقات.[1]
- الخادم يعرض `/healthz` لفحص الصحة. لا يعتبر `ok` إثباتًا أن سلسلة Google والتطبيق صحيحة.

## 8. تدوير المفتاح

لتغيير مفتاح الخروج، أنشئ مفتاحًا طويلًا جديدًا من أحرف وأرقام فقط، وعدّل الملف على VPS:

```bash
sudoedit /etc/zyrln-relay.env
```

حدّث السطر `ZYRLN_RELAY_KEY=...`، ثم أعد تشغيل الخدمة:

```bash
sudo systemctl restart zyrln-relay
sudo systemctl status zyrln-relay --no-pager
```

بعدها حدّث `EXIT_RELAY_KEY` في Apps Script، وانشر **New version**. أثناء التحديث لن تتطابق المفاتيح لحظيًا؛ أكمل الخطوتين تباعًا واختبر الاتصال.

## استكشاف الأخطاء

**فشل تنزيل حزمة GitHub:** افحص اتصال الخادم الصادر إلى GitHub وDNS، ثم أعد المحاولة. المثبت لا يجلب أو ينفذ shell script من الإنترنت مباشرة؛ بل ينزّل الحزمة الرسمية ويستخرج منها الملف التنفيذي المطابق للمعمارية.

**`healthz` المحلي يفشل:** اعرض سجل الخدمة عبر `journalctl -u zyrln-relay -n 100 --no-pager`. تحقق من ملف `/etc/zyrln-relay.env`، والمنفذ المستخدم، وصلاحيات الخدمة.

**`healthz` الخارجي يفشل لكن المحلي يعمل:** افحص جدار مزود VPS أولًا، ثم UFW أو أي جدار محلي آخر. تأكد أيضًا أنك تختبر IP العام والمنفذ `8787/TCP`.

**Apps Script يجيب Unauthorized:** طابق `AUTH_KEY` مع Key التطبيق، وطابق `EXIT_RELAY_KEY` مع `ZYRLN_RELAY_KEY` على الخادم. بعد أي تعديل، أنشئ إصدار نشر جديد.

**الخدمة تعمل لكن بعض التطبيقات لا تعمل:** تأكد أن التطبيق يستخدم إعداد Apps Script الصحيح. تذكر أن النفق TCP فقط؛ قد لا تعمل وظائف UDP أو المكالمات الصوتية.

## مصادر رسمية

[1]: https://github.com/ajavadinezhad/zyrln "شرح بنية Zyrln وإعداد الـrelay"
[2]: https://ubuntu.com/server/docs/how-to/security/firewalls "توثيق Ubuntu لجدار UFW"
[3]: https://developers.google.com/apps-script/guides/web "توثيق Google Apps Script Web Apps"
[4]: https://github.com/ajavadinezhad/zyrln/blob/main/docs/fa/guide.md "دليل استخدام Zyrln على Android"
