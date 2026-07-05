# Dynamic Island for Mac 🏝️

**MacBook çentiğini (notch) iPhone'daki Dynamic Island gibi etkileşimli bir merkeze dönüştüren ücretsiz ve açık kaynak macOS uygulaması.**

NotchBox gibi ücretli uygulamalara açık kaynak bir alternatif: tüm "Pro" özellikler ücretsiz, üstüne **son 20 pano öğesini saklayan pano geçmişi** eklendi. Reklam yok, pop-up yok, abonelik yok.

> A free, open-source Dynamic Island for the Mac notch — file shelf, AirDrop drop zone,
> music controls, clipboard history (last 20 items), pomodoro, calendar, camera mirror,
> mini browser and more. MIT licensed.

## Özellikler

| | |
|---|---|
| 📋 **Pano Geçmişi** | Kopyaladığınız **son 20 öğe** (metin, bağlantı, dosya, görsel) saklanır; tek tıkla yeniden kopyalanır. Parola yöneticilerinden gelen gizli içerik kaydedilmez. |
| 🗂️ **Dosya Rafı** | Dosyaları çentiğe sürükleyip bırakın, geçici olarak parklansın; gerektiğinde dışarı sürükleyin. Kopyalar App Support'ta tutulur — orijinal taşınsa bile raf çalışır. |
| 📡 **AirDrop** | Dosyayı çentikteki AirDrop bölgesine bırakın, paylaşım paneli anında açılır. |
| 🎵 **Müzik** | Apple Music ve Spotify: albüm kapağı, ilerleme çubuğu, önceki/oynat/sonraki, ritim animasyonu. Kapalı moddayken çentiğin yanında mini EQ. |
| 🍅 **Pomodoro** | Ayarlanabilir odak/mola süreleri, tur sayacı; çalışırken kapalı modda geri sayım görünür. |
| ⏱️ **Geri Sayım & Kronometre** | Hızlı zamanlayıcılar, bitince ses + haptik geri bildirim. |
| 📅 **Takvim & Anımsatıcılar** | Önümüzdeki 7 günün etkinlikleri ve bekleyen anımsatıcılar; çentikten tamamlayın. |
| 🪞 **Kamera Aynası** | Toplantı öncesi hızlı görünüş kontrolü — sekme kapanınca kamera kapanır. |
| 🌐 **Mini Tarayıcı** | Pencere değiştirmeden çentik içinde arama/gezinme (WKWebView). |
| 📝 **Notlar & Yer İmleri** | Hızlı not alma, bağlantı kaydetme. |
| 💧 **Su Takibi** | Günlük bardak sayacı, gece yarısı otomatik sıfırlanır. |
| 🔢 **Sayaç & Kalan Günler** | Genel amaçlı sayaç + önemli tarihlere geri sayım. |
| 📊 **Sistem Monitörü** | CPU, RAM, pil; kapalı modda pil yüzdesi, genişlemiş modda ağ hızı. |
| 🚀 **Uygulama Kısayolları** | Favori uygulamalarınızı çentikten tek tıkla başlatın. |
| ⚙️ **Sistem Entegrasyonu** | Oturum açılışında başlatma, Dock'ta görünmez (menü çubuğu uygulaması), hover/tıklama ile açılma seçeneği, ESC ile kapatma, haptik geri bildirim. |
| 🎨 **Kişiselleştirme** | 6 vurgu rengi, 3 panel boyutu, kapalı mod sol/sağ bölge içeriği (saat/tarih/pil/ağ hızı), açılma-kapanma gecikmeleri, ekolayzır ve haptik aç/kapa, kullanılmayan sekmeleri gizleme. |

Çentiği olmayan Mac'lerde (iMac, Mac mini, eski MacBook'lar) üst-ortada **simüle bir ada** çizilir — tüm özellikler aynen çalışır.

## Kurulum

Xcode gerekmez — Command Line Tools yeterli (`xcode-select --install`).

```bash
git clone <repo-url> dynamicIsland
cd dynamicIsland
./build-app.sh --run
```

Script `build/DynamicIsland.app` üretir ve başlatır. Kalıcı kullanım için `.app`'i `/Applications` klasörüne taşıyın (oturum açılışında başlatma özelliği için önerilir).

### İzinler

Özellikler ilk kullanımda ilgili izni ister; tümü isteğe bağlıdır:

- **Otomasyon (Apple Events)** — müzik kontrolü için (Apple Music / Spotify)
- **Takvimler & Anımsatıcılar** — takvim sekmesi için
- **Kamera** — ayna sekmesi için

Uygulama hiçbir veri toplamaz, ağa yalnızca Spotify albüm kapağı indirmek ve mini tarayıcı için çıkar.

## Kullanım

- **Genişlet:** İmleci çentiğe getirin (veya tıklayın — Ayarlar'dan seçilebilir)
- **Dosya parkla:** Herhangi bir dosyayı çentiğe sürükleyin — raf otomatik açılır
- **AirDrop:** Dosyayı Ana Sayfa'daki AirDrop bölgesine bırakın
- **Pano:** Pano sekmesinde herhangi bir öğeye tıklayın → yeniden kopyalanır
- **Kapat:** İmleci uzaklaştırın, dışarı tıklayın veya ESC'ye basın
- **Menü çubuğu:** ✨ simgesinden ayarlar ve çıkış
- **Ayarlar:** Modern sidebar'lı pencere — Genel / Görünüm / Modüller / Veriler / Hakkında

## Mimari

Saf Swift + SwiftUI + AppKit, sıfır harici bağımlılık. SwiftPM executable hedefi;
`build-app.sh` bundle'ı elle kurup ad-hoc imzalar.

```
Sources/DynamicIsland/
├── App.swift                  # @main giriş noktası (accessory app)
├── AppDelegate.swift          # Manager'ların sahibi, status item, ESC + tık monitörleri
├── NotchWindow.swift          # Şeffaf, kenarlıksız, her zaman üstte NSPanel
├── NotchViewModel.swift       # Genişleme/daraltma durum makinesi
├── Managers/                  # Pano, raf, müzik, takvim, kamera, ağ, sistem, zamanlayıcı…
├── Views/                     # CollapsedView, ExpandedView + 9 sekme + Ayarlar
└── Support/                   # Preferences, geometri, kalıcılık, drop yardımcıları
```

Önemli teknik noktalar:

- Pencere kapalıyken adayı saracak kadar küçüktür, yalnızca genişleyince büyür — ekranın
  geri kalanındaki tıklamaları asla engelleyemez.
- Çentik geometrisi `NSScreen.auxiliaryTopLeftArea/safeAreaInsets` ile hesaplanır.
- Müzik, **yalnızca zaten çalışan** uygulamalara Apple Events gönderir (uygulama başlatmaz).
- Pano izleyici `changeCount` poll eder (0.5 sn); kendi yazdıklarını yeniden yakalamaz.

## Uygulama İkonu

İkon programatik üretilir: `swift scripts/make-icon.swift çıktı.png` 1024px master PNG çizer;
`sips` + `iconutil` ile `AppBundle/AppIcon.icns` derlenir (depoya dahildir).

## Lisans

[MIT](LICENSE) — dilediğiniz gibi kullanın, katkılara açıktır.
