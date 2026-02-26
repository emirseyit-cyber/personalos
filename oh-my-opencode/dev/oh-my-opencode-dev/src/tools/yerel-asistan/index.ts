import { tool, type ToolDefinition } from "@opencode-ai/plugin/tool"
import * as fs from "fs"
import * as path from "path"
import * as os from "os"
import { execSync, spawn } from "child_process"

/**
 * ╔══════════════════════════════════════════════════════════════════════════════╗
 * ║         🔱 OMEGA SUPER v3.0 - OPENCODE ENTEGRASYON v2.0.753              ║
 * ║         TÜM SİSTEMLER BİR ARADA: OpenCode + Ollama + Vy AI + Hafıza      ║
 * ╚══════════════════════════════════════════════════════════════════════════════╝
 * 
 * KURULUŞ: 2026-01-18
 * GÜNCELLEME: 2026-02-26
 * VERSİYON: v3.0-ULTIMATE
 */

// ==================== KONSTANTLAR ====================

const OPENCODE_CLI = "D:\\OpenCode\\opencode-cli.exe"
const COMMENT_CHECKER = "D:\\OpenCode\\oh-my-opencode\\bin\\comment-checker.exe"
const VY_EXE = "C:\\Users\\akina\\AppData\\Local\\Vy\\Vy.exe"
const AUTOMATION_SCRIPT = "D:\\OpenCode\\omega_automation.py"
const PYTHON_EXE = "C:\\Users\\akina\\scoop\\apps\\python\\current\\python.exe"

const OLLAMA_MODEL = "llama3.2"
const OLLAMA_URL = "http://localhost:11434/api/chat"
const OPENCODE_MODEL = "opencode/gpt-5-nano"

const DATA_DIR = "Omega_Super_Data"
const HAFIZA_YOLU = path.join(DATA_DIR, "hafiza.json")
const LOG_YOLU = path.join(DATA_DIR, "sistem.log")
const TEST_LOG_YOLU = path.join(DATA_DIR, "testler.json")

// ==================== DEĞİŞKENLER ====================

const hafiza: Map<string, string> = new Map()
const sohbet: Array<{rol: string, icerik: string}> = []
const islemler: Array<{tur: string, mesaj: string, ms: number, zaman: string}> = []

// ==================== YARDIMCI FONKSİYONLAR ====================

function veriDiziniOlustur(): void {
  if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true })
  }
}

function hafizaYukle(): Record<string, unknown> {
  veriDiziniOlustur()
  try {
    if (fs.existsSync(HAFIZA_YOLU)) {
      const data = fs.readFileSync(HAFIZA_YOLU, "utf-8")
      return JSON.parse(data)
    }
  } catch (e) {
    // Hata yok sayılır
  }
  return { kurulus: "2026-01-18", islem_sayisi: 0, hatiralar: [] }
}

function hafizaKaydet(data: Record<string, unknown>): void {
  veriDiziniOlustur()
  fs.writeFileSync(HAFIZA_YOLU, JSON.stringify(data, null, 2), "utf-8")
}

function logYaz(mesaj: string): void {
  veriDiziniOlustur()
  const zaman = new Date().toISOString()
  fs.appendFileSync(LOG_YOLU, `[${zaman}] ${mesaj}\n`, "utf-8")
}

// ==================== VY AI FONKSİYONLARI ====================

function vyKontrol(): { var: boolean, versiyon: string } {
  try {
    const result = execSync(`tasklist /FI "IMAGENAME eq Vy.exe" /NH`, { encoding: "utf-8" })
    const varMi = result.toLowerCase().includes("vy.exe")
    
    return {
      var: varMi,
      versiyon: varMi ? "0.7.10" : "Kurulu değil"
    }
  } catch (e) {
    return { var: false, versiyon: "Kontrol hatası" }
  }
}

function vyBaslat(): string {
  try {
    const vyDurum = vyKontrol()
    if (vyDurum.var) {
      return "⚠️ Vy AI zaten çalışıyor"
    }
    
    spawn(VY_EXE, [], {
      detached: true,
      stdio: "ignore",
      cwd: path.dirname(VY_EXE)
    })
    
    logYaz("Vy AI başlatıldı")
    return "✅ Vy AI başlatıldı\n💡 @ tuşu ile komut verebilirsin"
  } catch (e) {
    return `❌ Vy başlatma hatası: ${e}`
  }
}

function vyDurdur(): string {
  try {
    execSync(`taskkill /F /IM Vy.exe`, { encoding: "utf-8" })
    logYaz("Vy AI durduruldu")
    return "✅ Vy AI durduruldu"
  } catch (e) {
    return "ℹ️ Vy zaten çalışmıyordu"
  }
}

// ==================== SİSTEM KONTROL FONKSİYONLARI ====================

function sistemKontrol(): { opencode: boolean, ollama: boolean, checker: boolean, vy: boolean } {
  let ollamaVar = false
  try {
    fetch(OLLAMA_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ model: OLLAMA_MODEL, messages: [], stream: false })
    })
    ollamaVar = true
  } catch (e) {
    ollamaVar = false
  }
  
  const vyDurum = vyKontrol()
  
  return {
    opencode: fs.existsSync(OPENCODE_CLI),
    ollama: ollamaVar,
    checker: fs.existsSync(COMMENT_CHECKER),
    vy: vyDurum.var
  }
}

// ==================== OLLAMA FONKSİYONLARI ====================

async function ollamaSorgula(prompt: string, sistemBilgi: string = ""): Promise<string> {
  try {
    const sistemTalimati = `Sen yardımcı bir AI asistanısın. Kullanıcı hafızası: ${sistemBilgi}`
    
    const response = await fetch(OLLAMA_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: OLLAMA_MODEL,
        messages: [
          { role: "system", content: sistemTalimati },
          ...sohbet.slice(-10).map(s => ({ role: s.rol, content: s.icerik })),
          { role: "user", content: prompt }
        ],
        stream: false
      })
    })

    if (!response.ok) {
      return `AI Hata: ${response.status}`
    }

    const data = await response.json() as { message?: { content?: string } }
    return data.message?.content || "Boş yanıt"
  } catch (e) {
    return `Bağlantı hatası: ${e}. Ollama çalışıyor mu?`
  }
}

// ==================== OPENCODECLI FONKSİYONLARI ====================

function opencodeCalistir(mesaj: string): { cikti: string, ms: number, basarili: boolean } {
  const t0 = Date.now()
  
  try {
    const cikti = execSync(
      `"${OPENCODE_CLI}" -m ${OPENCODE_MODEL} run "${mesaj}"`,
      { encoding: "utf-8", timeout: 60000, stdio: ["pipe", "pipe", "pipe"] }
    )
    logYaz(`OpenCode: ${mesaj.substring(0, 20)} | ${Date.now() - t0}ms`)
    return { cikti: cikti.trim(), ms: Date.now() - t0, basarili: true }
  } catch (e: unknown) {
    const hata = e instanceof Error ? e.message : String(e)
    logYaz(`OpenCode Hata: ${hata}`)
    return { cikti: `❌ Hata: ${hata.substring(0, 100)}`, ms: Date.now() - t0, basarili: false }
  }
}

// ==================== WEB ARAMA FONKSİYONLARI ====================

async function webAra(sorgu: string): Promise<string> {
  try {
    const aramaUrl = `https://duckduckgo.com/?q=${encodeURIComponent(sorgu)}&format=json`
    
    const response = await fetch(aramaUrl, {
      method: "GET",
      headers: { "Accept": "application/json" }
    })
    
    if (!response.ok) {
      return `Web arama hatası: ${response.status}`
    }
    
    const data = await response.json() as { Results?: Array<{ Text?: string, URL?: string }> }
    
    if (data.Results && data.Results.length > 0) {
      const sonuclar = data.Results.slice(0, 5).map((r, i) => 
        `${i + 1}. ${r.Text || "Başlık yok"}\n   📎 ${r.URL || ""}`
      ).join("\n")
      return `🌐 Web Arama Sonuçları:\n\n${sonuclar}`
    }
    
    return "Sonuç bulunamadı"
  } catch (e) {
    return `Web arama hatası: ${e}`
  }
}

// ==================== DOSYA FONKSİYONLARI ====================

function dosyaOku(dosyaYolu: string): string {
  try {
    const tamYol = path.isAbsolute(dosyaYolu) ? dosyaYolu : path.join(os.homedir(), dosyaYolu)
    if (!fs.existsSync(tamYol)) return `❌ Dosya bulunamadı: ${dosyaYolu}`
    
    const icerik = fs.readFileSync(tamYol, "utf-8")
    return `📄 ${dosyaYolu} (${icerik.length} karakter):\n\n${icerik.substring(0, 2000)}`
  } catch (e) {
    return `❌ Dosya okuma hatası: ${e}`
  }
}

function dosyaYaz(dosyaYolu: string, icerik: string): string {
  try {
    const tamYol = path.isAbsolute(dosyaYolu) ? dosyaYolu : path.join(os.homedir(), dosyaYolu)
    const dizin = path.dirname(tamYol)
    
    if (!fs.existsSync(dizin)) {
      fs.mkdirSync(dizin, { recursive: true })
    }
    
    fs.writeFileSync(tamYol, icerik, "utf-8")
    logYaz(`Dosya yazıldı: ${dosyaYolu}`)
    return `✅ Dosya yazıldı: ${dosyaYolu} (${icerik.length} karakter)`
  } catch (e) {
    return `❌ Dosya yazma hatası: ${e}`
  }
}

function dosyaListele(dizin: string): string {
  try {
    const tamYol = path.isAbsolute(dizin) ? dizin : path.join(os.homedir(), dizin)
    if (!fs.existsSync(tamYol)) return `❌ Dizin bulunamadı: ${dizin}`
    
    const dosyalar = fs.readdirSync(tamYol)
    const liste = dosyalar.slice(0, 30).map(d => {
      const tam = path.join(tamYol, d)
      const istatistik = fs.statSync(tam)
      const tip = istatistik.isDirectory() ? "📁" : "📄"
      return `${tip} ${d}`
    }).join("\n")
    
    return `📂 ${dizin} (${dosyalar.length} öğe):\n\n${liste}`
  } catch (e) {
    return `❌ Dizin okuma hatası: ${e}`
  }
}

// ==================== HAVA DURUMU FONKSİYONLARI ====================

async function havaDurumu(sehir: string): Promise<string> {
  try {
    const geoResponse = await fetch(
      `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(sehir)}&count=1`
    )
    
    if (!geoResponse.ok) return "❌ Şehir bulunamadı"
    
    const geoData = await geoResponse.json() as { results?: Array<{ latitude: number, longitude: number, name: string, country: string }> }
    
    if (!geoData.results || geoData.results.length === 0) {
      return "❌ Şehir bulunamadı"
    }
    
    const konum = geoData.results[0]
    const havaResponse = await fetch(
      `https://api.open-meteo.com/v1/forecast?latitude=${konum.latitude}&longitude=${konum.longitude}&current=temperature_2m,weather_code,wind_speed_10m`
    )
    
    const havaData = await havaResponse.json() as { current?: { temperature_2m?: number, weather_code?: number, wind_speed_10m?: number } }
    
    const sicaklik = havaData.current?.temperature_2m ?? 0
    const ruzgar = havaData.current?.wind_speed_10m ?? 0
    const kod = havaData.current?.weather_code ?? 0
    
    const durumlar: Record<number, string> = {
      0: "☀️ Açık", 1: "🌤️ Parçalı Bulutlu", 2: "⛅ Bulutlu", 3: "☁️ Kapalı",
      45: "🌫️ Sis", 48: "🌫️ Sis", 51: "🌧️ Çisenti", 61: "🌧️ Yağmur",
      71: "❄️ Kar", 95: "⛈️ Fırtına"
    }
    
    const durum = durumlar[kod] || "Bilinmiyor"
    
    return `🌡️ ${konum.name}, ${konum.country}
═══════════════════════
${durum}
Sıcaklık: ${sicaklik}°C
Rüzgar: ${ruzgar} km/s
═══════════════════════`
  } catch (e) {
    return `❌ Hava durumu hatası: ${e}`
  }
}

// ==================== OTOMATİK TEST FONKSİYONLARI ====================

interface TestSonuc {
  tur: string
  basarili: boolean
  ms: number
  zaman: string
  hata?: string
}

function testSonucKaydet(sonuc: TestSonuc): void {
  veriDiziniOlustur()
  let testler: TestSonuc[] = []
  
  try {
    if (fs.existsSync(TEST_LOG_YOLU)) {
      testler = JSON.parse(fs.readFileSync(TEST_LOG_YOLU, "utf-8"))
    }
  } catch (e) {
    testler = []
  }
  
  testler.push(sonuc)
  testler = testler.slice(-100)
  
  fs.writeFileSync(TEST_LOG_YOLU, JSON.stringify(testler, null, 2), "utf-8")
}

async function otomatikTest(): Promise<string> {
  const sonuclar: string[] = []
  let basarili = 0
  let toplam = 0
  
  const sys = sistemKontrol()
  toplam++
  if (sys.opencode && sys.checker) basarili++
  sonuclar.push(`${sys.opencode && sys.checker ? "✅" : "❌"} Sistem kontrol`)
  
  toplam++
  if (sys.vy) {
    basarili++
    sonuclar.push("✅ Vy AI")
  } else {
    sonuclar.push("⚠️ Vy AI (kapalı)")
  }
  
  try {
    const t0 = Date.now()
    await fetch(OLLAMA_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ model: OLLAMA_MODEL, messages: [], stream: false })
    })
    const ms = Date.now() - t0
    toplam++
    basarili++
    sonuclar.push(`✅ Ollama (${ms}ms)`)
    testSonucKaydet({ tur: "ollama", basarili: true, ms, zaman: new Date().toISOString() })
  } catch (e) {
    toplam++
    sonuclar.push(`❌ Ollama: ${e}`)
    testSonucKaydet({ tur: "ollama", basarili: false, ms: 0, zaman: new Date().toISOString(), hata: String(e) })
  }
  
  try {
    const t0 = Date.now()
    execSync(`"${OPENCODE_CLI}" -m ${OPENCODE_MODEL} run "test"`, { encoding: "utf-8", timeout: 30000 })
    const ms = Date.now() - t0
    toplam++
    basarili++
    sonuclar.push(`✅ OpenCode CLI (${ms}ms)`)
    testSonucKaydet({ tur: "opencode", basarili: true, ms, zaman: new Date().toISOString() })
  } catch (e) {
    toplam++
    sonuclar.push(`❌ OpenCode CLI: ${e}`)
    testSonucKaydet({ tur: "opencode", basarili: false, ms: 0, zaman: new Date().toISOString(), hata: String(e) })
  }
  
  const oran = Math.round((basarili / toplam) * 100)
  logYaz(`Otomatik test: ${basarili}/${toplam} başarılı (${oran}%)`)
  
  return `🔄 OTOMATİK TEST SONUÇLARI
══════════════════════════════
${sonuclar.join("\n")}
══════════════════════════════
📊 Toplam: ${basarili}/${toplam} (${oran}%)
⏰ ${new Date().toLocaleString("tr-TR")}
══════════════════════════════`
}

function testGoster(): string {
  try {
    if (!fs.existsSync(TEST_LOG_YOLU)) return "❌ Test kaydı yok"
    
    const testler = JSON.parse(fs.readFileSync(TEST_LOG_YOLU, "utf-8")) as TestSonuc[]
    const son5 = testler.slice(-5).reverse()
    
    const satirlar = son5.map(t => 
      `${t.basarili ? "✅" : "❌"} [${t.zaman.substring(11, 19)}] ${t.tur} - ${t.ms}ms${t.hata ? ` (${t.hata.substring(0, 30)})` : ""}`
    )
    
    return `📊 SON TESTLER:\n\n${satirlar.join("\n")}`
  } catch (e) {
    return `❌ Test okuma hatası: ${e}`
  }
}

// ==================== OTOMATİK BAŞLATMA FONKSİYONLARI ====================

function otomatikBaslat(aktif: boolean): string {
  try {
    const startupKlasoru = path.join(os.homedir(), "AppData", "Roaming", "Microsoft", "Windows", "Start Menu", "Programs", "Startup")
    const scriptYolu = path.join(os.homedir(), "omega_auto_start.bat")
    const pythonYolu = "C:\\Users\\akina\\scoop\\apps\\python\\current\\python.exe"
    const omegaYolu = "D:\\OpenCode\\omega_auto.py"
    
    if (aktif) {
      const batchIcerik = `@echo off\n"${pythonYolu}" "${omegaYolu}"\n`
      fs.writeFileSync(scriptYolu, batchIcerik, "utf-8")
      
      const vbsScript = `
Set WshShell = CreateObject("WScript.Shell")
Set shortcut = WshShell.CreateShortcut("${startupKlasoru}\\OmegaSuper.lnk")
shortcut.TargetPath = "${scriptYolu}"
shortcut.WorkingDirectory = "D:\\OpenCode"
shortcut.Description = "Omega Super Auto Start"
shortcut.Save
`
      const vbsYolu = path.join(os.homedir(), "omega_shortcut.vbs")
      fs.writeFileSync(vbsYolu, vbsScript, "utf-8")
      
      execSync(`cscript //Nologo "${vbsYolu}"`, { encoding: "utf-8" })
      fs.unlinkSync(vbsYolu)
      
      logYaz("Otomatik başlatma aktif")
      return "✅ Windows başlangıcına eklendi\n🔄 Bilgisayar açılınca otomatik çalışacak"
    } else {
      const ksayotYolu = path.join(startupKlasoru, "OmegaSuper.lnk")
      const batchYolu = path.join(os.homedir(), "omega_auto_start.bat")
      
      if (fs.existsSync(ksayotYolu)) fs.unlinkSync(ksayotYolu)
      if (fs.existsSync(batchYolu)) fs.unlinkSync(batchYolu)
      
      logYaz("Otomatik başlatma kapatıldı")
      return "✅ Windows başlangıcından kaldırıldı"
    }
  } catch (e) {
    return `❌ Otomatik başlatma hatası: ${e}`
  }
}

// ==================== HASH FONKSİYONLARI ====================

function hashOlustur(veri: string): string {
  const crypto = require("crypto")
  return crypto.createHash("sha256").update(veri).digest("hex")
}

// ==================== ANA TOOL ====================

export function createYerelAsistanTool(): Record<string, ToolDefinition> {
  const omega_super: ToolDefinition = tool({
    description: `🔱 OMEGA SUPER v3.0 - TAM OTOMATİK SİSTEM
    
    ═════════════════════════════════════════
    📡 OPENCODECLI:
    • opencode [mesaj] - OpenCode CLI ile gerçek icraat
    
    🤖 YAPAY ZEKA:
    • ollama [mesaj] - Ollama AI (yerel) ile sohbet
    
    🧠 HAFIZA:
    • ogren soru=cevap - Bilgi öğren
    • hatirla konu - Hafızadan ara
    • hafiza - Tüm hafızayı göster
    
    🟣 VY AI:
    • vy durum - Vy AI durumunu kontrol et
    • vy baslat - Vy AI'yı başlat
    • vy durdur - Vy AI'yı durdur
    
    ⚡ OTO (VY'NİN YAPTIĞI HER ŞEYİ YAPAR):
    • oto click <x> <y> - Mouse tıkla
    • oto move <x> <y> - Mouse hareket
    • oto type <metin> - Yazı yaz
    • oto press <tus> - Klavye tusu
    • oto screenshot - Ekran görüntüsü
    • oto ocr - OCR oku
    • oto start <uygulama> - Uygulama başlat
    • oto stop <isim> - Uygulama durdur
    • oto processes - Proses listele
    
    🌐 İNTERNET:
    • web [sorgu] - Web araması yap
    • hava [şehir] - Hava durumu sorgula
    
    📁 DOSYA:
    • oku [dosya] - Dosya oku
    • yaz dosya=icerik - Dosya yaz
    • liste [dizin] - Dizin listele
    
    🛠️ SİSTEM:
    • sistem - Sistem durumunu kontrol et
    • hash [veri] - SHA256 hash oluştur
    • test - Otomatik test çalıştır
    • testler - Test sonuçlarını göster
    • baslat - Otomatik başlat
    • durdur - Otomatik başlatmayı kaldır
    • temizle - Her şeyi temizle
    • log - İşlem geçmişini göster
    • yardim - Bu menüyü göster`,
    
    args: {
      komut: tool.schema.string().describe("Komut: opencode, ollama, ogren, hatirla, hafiza, vy, oto, web, hava, oku, yaz, liste, sistem, hash, test, testler, baslat, durdur, temizle, log, yardim"),
      mesaj: tool.schema.string().optional().describe("Parametre veya mesaj")
    },
    
    execute: async (args: Record<string, unknown>, _context) => {
      const komut = String(args.komut || "").toLowerCase()
      const mesaj = String(args.mesaj || "")
      const t0 = Date.now()

      try {
        // ===== OPENCODECLI =====
        if (komut === "opencode" || komut === "oc") {
          if (!mesaj) return "❌ Mesaj belirtin"
          
          const sonuc = opencodeCalistir(mesaj)
          
          islemler.push({
            tur: "opencode",
            mesaj: mesaj.substring(0, 50),
            ms: sonuc.ms,
            zaman: new Date().toISOString()
          })
          
          const data = hafizaYukle()
          data.islem_sayisi = (data.islem_sayisi as number) + 1
          if (!data.hatiralar) data.hatiralar = []
          ;(data.hatiralar as Array<unknown>).push({
            tur: "opencode",
            mesaj: mesaj.substring(0, 50),
            ms: sonuc.ms,
            zaman: new Date().toISOString()
          })
          hafizaKaydet(data)
          
          return `🔱 [OpenCode CLI] ${sonuc.ms}ms\n\n${sonuc.cikti}`
        }

        // ===== OLLAMA AI =====
        if (komut === "ollama" || komut === "ai" || komut === "sorgu") {
          if (!mesaj) return "❌ Mesaj belirtin"
          
          const sistemBilgi = Array.from(hafiza.entries()).map(([k, v]) => `${k}: ${v}`).join(" | ")
          const yanit = await ollamaSorgula(mesaj, sistemBilgi)
          
          sohbet.push({ rol: "user", icerik: mesaj })
          sohbet.push({ rol: "assistant", icerik: yanit })
          if (sohbet.length > 20) sohbet.shift()
          
          const ms = Date.now() - t0
          
          return `🤖 [Ollama AI] ${ms}ms\n\n${yanit}`
        }

        // ===== ÖĞREN =====
        if (komut === "ogren" || komut === "o" || komut === "öğren") {
          if (!mesaj.includes("=")) return "❌ Format: ogren soru = cevap"
          
          const parcalar = mesaj.split("=")
          const soru = parcalar[0].trim().toLowerCase()
          const cevap = parcalar.slice(1).join("=").trim()
          
          hafiza.set(soru, cevap)
          
          const data = hafizaYukle()
          if (!data.ogrenilen) data.ogrenilen = {}
          ;(data.ogrenilen as Record<string, string>)[soru] = cevap
          hafizaKaydet(data)
          
          logYaz(`Öğrenildi: ${soru}`)
          return `✅ Öğrenildi: "${soru}" = "${cevap}"`
        }

        // ===== HATIRLA =====
        if (komut === "hatirla" || komut === "h") {
          if (!mesaj) return "❌ Konu belirtin"
          
          const arama = mesaj.toLowerCase()
          
          for (const [soru, cevap] of hafiza.entries()) {
            if (soru.includes(arama) || arama.includes(soru)) {
              return `📌 [Hafızada Bulundu]:\n${soru} = ${cevap}`
            }
          }
          
          const data = hafizaYukle()
          if (data.ogrenilen) {
            for (const [soru, cevap] of Object.entries(data.ogrenilen as Record<string, string>)) {
              if (soru.includes(arama) || arama.includes(soru)) {
                return `📌 [Dosyadan Bulundu]:\n${soru} = ${cevap}`
              }
            }
          }
          
          return "❌ Hafızada bulunamadı"
        }

        // ===== HAFIZA GÖSTER =====
        if (komut === "hafiza" || komut === "hf") {
          const bilgiler = Array.from(hafiza.entries()).map(([k, v]) => `• ${k} = ${v}`)
          
          const data = hafizaYukle()
          let cikti = `🔱 OMEGA SUPER v3.0 - HAFIZA\n`
          cikti += `═══════════════════════════════\n`
          cikti += `📊 Toplam İşlem: ${data.islem_sayisi || 0}\n`
          cikti += `🧠 Hafıza Boyutu: ${hafiza.size}\n`
          cikti += `═══════════════════════════════\n`
          
          if (bilgiler.length > 0) {
            cikti += `\n📚 Öğrenilen Bilgiler:\n${bilgiler.join("\n")}\n`
          }
          
          if (data.hatiralar && (data.hatiralar as Array<unknown>).length > 0) {
            cikti += `\n📜 Son İşlemler:\n`
            const sonIslemler = (data.hatiralar as Array<{tur: string, mesaj: string, ms: number}>).slice(-5)
            for (const is of sonIslemler) {
              cikti += `  • [${is.tur}] ${is.mesaj} (${is.ms}ms)\n`
            }
          }
          
          return cikti
        }

        // ===== VY AI KONTROL =====
        if (komut === "vy" || komut === "vyai") {
          if (!mesaj) {
            const vyDurum = vyKontrol()
            return `🟣 VY AI DURUMU
══════════════════════════════
${vyDurum.var ? "✅ ÇALIŞIYOR" : "❌ KAPALI"}
Versiyon: ${vyDurum.versiyon}
══════════════════════════════
Komutlar:
  vy durum   - Durumu göster
  vy baslat  - Vy AI'yı başlat
  vy durdur  - Vy AI'yı durdur
══════════════════════════════`
          }
          
          const vyKomut = mesaj.toLowerCase()
          
          if (vyKomut === "durum" || vyKomut === "status") {
            const vyDurum = vyKontrol()
            return `🟣 VY AI: ${vyDurum.var ? "✅ ÇALIŞIYOR" : "❌ KAPALI"}`
          }
          
          if (vyKomut === "baslat" || vyKomut === "start" || vyKomut === "aç") {
            return vyBaslat()
          }
          
          if (vyKomut === "durdur" || vyKomut === "stop" || vyKomut === "kapat") {
            return vyDurdur()
          }
          
          return "❌ Vy komutu: durum, baslat, durdur"
        }

        // ===== SİSTEM KONTROL =====
        if (komut === "sistem" || komut === "sys" || komut === "durum") {
          const sys = sistemKontrol()
          
          return `🔱 OMEGA SİSTEM DURUMU v3.0
══════════════════════════════
✅ OpenCode CLI : ${sys.opencode ? "AÇIK" : "KAPALI"}
   Path: ${OPENCODE_CLI}

🤖 Ollama       : ${sys.ollama ? "AÇIK" : "KAPALI"}
   Model: ${OLLAMA_MODEL}

🟣 Vy AI        : ${sys.vy ? "ÇALIŞIYOR" : "KAPALI"}
   Path: ${VY_EXE}

✅ comment-checker: ${sys.checker ? "AÇIK" : "KAPALI"}

📊 İstatistikler:
   • İşlem Sayısı: ${(hafizaYukle().islem_sayisi || 0)}
   • Hafıza Boyutu: ${hafiza.size}
   • Aktif Sohbet: ${sohbet.length / 2}
══════════════════════════════`
        }

        // ===== HASH OLUŞTUR =====
        if (komut === "hash" || komut === "sha") {
          if (!mesaj) return "❌ Veri belirtin"
          
          const hash = hashOlustur(mesaj)
          return `🔐 SHA256 Hash:\n\n${hash}`
        }

        // ===== TEMİZLE =====
        if (komut === "temizle" || komut === "t" || komut === "clear") {
          hafiza.clear()
          sohbet.length = 0
          islemler.length = 0
          
          const data = { kurulus: "2026-01-18", islem_sayisi: 0, hatiralar: [], ogrenilen: {} }
          hafizaKaydet(data)
          
          logYaz("Hafıza temizlendi")
          return "✅ Tüm hafıza temizlendi (hafıza, sohbet, işlemler)"
        }

        // ===== LOG GÖSTER =====
        if (komut === "log" || komut === "gecmis") {
          try {
            if (fs.existsSync(LOG_YOLU)) {
              const logIcerik = fs.readFileSync(LOG_YOLU, "utf-8")
              const satirlar = logIcerik.split("\n").filter(s => s.trim())
              const son5 = satirlar.slice(-10)
              return `📜 SON İŞLEM LOGLARI:\n\n${son5.join("\n")}`
            }
            return "❌ Log dosyası yok"
          } catch (e) {
            return `❌ Log okuma hatası: ${e}`
          }
        }

        // ===== WEB ARAMA =====
        if (komut === "web" || komut === "ara" || komut === "search") {
          if (!mesaj) return "❌ Arama sorgusu belirtin"
          return await webAra(mesaj)
        }

        // ===== DOSYA OKU =====
        if (komut === "oku" || komut === "read" || komut === "dosya") {
          if (!mesaj) return "❌ Dosya yolu belirtin"
          return dosyaOku(mesaj)
        }

        // ===== DOSYA YAZ =====
        if (komut === "yaz" || komut === "write") {
          if (!mesaj.includes("=")) return "❌ Format: yaz dosya=icerik"
          const parcalar = mesaj.split("=")
          const dosya = parcalar[0].trim()
          const icerik = parcalar.slice(1).join("=").trim()
          return dosyaYaz(dosya, icerik)
        }

        // ===== DİZİN LİSTELE =====
        if (komut === "liste" || komut === "dir" || komut === "ls" || komut === "list") {
          const hedef = mesaj || "."
          return dosyaListele(hedef)
        }

        // ===== HAVA DURUMU =====
        if (komut === "hava" || komut === "weather" || komut === "derece") {
          if (!mesaj) return "❌ Şehir belirtin"
          return await havaDurumu(mesaj)
        }

        // ===== OTOMATİK TEST =====
        if (komut === "test" || komut === "check") {
          return await otomatikTest()
        }

        // ===== TEST SONUÇLARI =====
        if (komut === "testler" || komut === "tests") {
          return testGoster()
        }

        // ===== OTOMATİK BAŞLAT =====
        if (komut === "baslat" || komut === "start" || komut === "auto") {
          return otomatikBaslat(true)
        }

        // ===== OTOMATİK DURDUR =====
        if (komut === "durdur" || komut === "stop" || komut === "disable") {
          return otomatikBaslat(false)
        }

        // ===== OTOMASYON =====
        if (komut === "oto" || komut === "automation" || komut === "auto") {
          if (!mesaj) {
            return `🔄 OMEGA OTOMASYON - VY YERİNE GEÇEN
            
🖱️ MOUSE:
  click <x> <y>     - Tıkla
  move <x> <y>      - Hareket et
  drag <x1> <y1> <x2> <y2> - Sürükle

⌨️ KLAVYE:
  type <metin>     - Yazı yaz
  press <tus>      - Tus bas (ctrl+c)

📸 EKRAN:
  screenshot        - Ekran görüntüsü
  ocr               - OCR oku
  bul <dosya>      - Görsel bul

🪟 PENCERE:
  activate <baslik> - Aktif et
  start <yol>      - Uygulama başlat
  stop <isim>      - Uygulama durdur
  processes        - Proses listele

⚡ WORKFLOW:
  workflow list     - Listele
  workflow run <isim> - Çalıştır`
          }
          
          // Automation scripti çalıştır
          try {
            const cikti = execSync(
              `"${PYTHON_EXE}" "${AUTOMATION_SCRIPT}" ${mesaj}`,
              { encoding: "utf-8", timeout: 30000 }
            )
            logYaz(`Oto: ${mesaj.substring(0, 20)}`)
            return `⚡ [OTOMASYON]\n\n${cikti}`
          } catch (e: unknown) {
            const hata = e instanceof Error ? e.message : String(e)
            return `❌ Otomasyon hatası: ${hata}`
          }
        }

        // ===== YARDIM =====
        if (komut === "yardim" || komut === "help" || komut === "?") {
          return `🔱 OMEGA SUPER v3.0 - YARDIM

══════════════════════════════
📡 OPENCODECLI:
  opencode [msg] - OpenCode CLI çalıştır

🤖 YAPAY ZEKA:
  ollama [msg]   - Ollama AI ile sohbet

🧠 HAFIZA:
  ogren k=v      - Bilgi öğren
  hatirla [konu] - Hafızadan ara
  hafiza         - Tüm hafızayı göster

🟣 VY AI:
  vy durum       - Vy AI durumunu kontrol et
  vy baslat      - Vy AI'yı başlat
  vy durdur      - Vy AI'yı durdur

🌐 İNTERNET:
  web [sorgu]    - Web araması yap
  hava [şehir]   - Hava durumu sorgula

📁 DOSYA:
  oku [dosya]    - Dosya oku
  yaz d=i        - Dosya yaz
  liste [dizin]  - Dizin listele

🛠️ SİSTEM:
  sistem         - Sistem durumunu göster
  hash [veri]    - SHA256 hash oluştur
  test           - Otomatik test çalıştır
  testler        - Test sonuçlarını göster
  baslat         - Otomatik başlat
  durdur         - Başlatmayı kaldır
  temizle        - Her şeyi temizle
  log            - İşlem geçmişini göster

══════════════════════════════`
        }

        return "❌ Bilinmeyen komut. 'yardim' yazarak tüm komutları görebilirsin."

      } catch (e) {
        return `❌ Sistem Hatası: ${e}`
      }
    }
  })

  return { omega_super }
}
