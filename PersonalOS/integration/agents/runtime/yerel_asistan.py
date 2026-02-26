#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
YEREL AI ASISTAN v4.3 - TAM ENTEGRASYON (GÜVENLİ & STABİL)
===========================================================
- SQL Injection koruması
- Resource leak önlemi  
- Thread safety
- Input validasyonu
- Hata yönetimi
- Yapılandırma dosyası desteği
"""

import os
import sys
import sqlite3
import subprocess
import json
import uuid
import datetime
import urllib.request
import urllib.error
import threading
import logging
import re
import yaml
from pathlib import Path
from contextlib import contextmanager
from typing import Optional, List, Dict, Generator, Any
from dataclasses import dataclass

# UTF-8 encoding for Windows
if sys.platform == 'win32':
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')

# ==================== YAPILANDIRMA YÖNETİMİ ====================

@dataclass
class Config:
    """Yapılandırma sınıfı"""
    ai_provider: str = "ollama"
    ai_model: str = "llama3.2"
    ai_api_url: str = "http://localhost:11434/api/chat"
    ai_timeout: int = 120
    openai_api_key: str = ""
    opencode_cli_path: str = "opencode"
    opencode_timeout: int = 300
    ps_timeout: int = 60
    db_name: str = "beyin.db"
    max_input_length: int = 10000
    max_memory_items: int = 1000
    command_whitelist: List[str] = None

    def __post_init__(self):
        if self.command_whitelist is None:
            self.command_whitelist = ['ls', 'dir', 'pwd', 'cd', 'mkdir', 'rm', 'cp', 'mv', 'git', 'npm', 'python', 'pip']

class ConfigManager:
    """Yapılandırma yöneticisi"""
    def __init__(self, config_dir: str = None):
        self.config_dir = Path(config_dir) if config_dir else Path.home() / ".yerel_asistan"
        self.config_file = self.config_dir / "config.yaml"
        self.config = self._load_config()

    def _load_config(self) -> Config:
        self.config_dir.mkdir(parents=True, exist_ok=True)
        if self.config_file.exists():
            try:
                with open(self.config_file, 'r', encoding='utf-8') as f:
                    data = yaml.safe_load(f)
                return Config(**data)
            except Exception as e:
                logging.warning(f"Config okuma hatası: {e}, varsayılanlar kullanılıyor")
        config = Config()
        config.openai_api_key = os.environ.get("OPENAI_API_KEY", "")
        self._save_config(config)
        return config

    def _save_config(self, config: Config):
        try:
            with open(self.config_file, 'w', encoding='utf-8') as f:
                yaml.dump(config.__dict__, f, default_flow_style=False, allow_unicode=True)
        except Exception as e:
            logging.error(f"Config kaydetme hatası: {e}")

    def get(self) -> Config:
        return self.config

# ==================== LOGGING YÖNETİMİ ====================

def setup_logging(data_dir: Path):
    log_dir = data_dir / "logs"
    log_dir.mkdir(exist_ok=True)
    log_file = log_dir / f"yerelai_{datetime.datetime.now().strftime('%Y%m%d')}.log"
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_file, encoding='utf-8'),
            logging.StreamHandler(sys.stdout)
        ]
    )
    return logging.getLogger("YerelAI")

# ==================== GÜVENLİK YÖNETİMİ ====================

class SecurityManager:
    def __init__(self, config: Config):
        self.config = config
        self.logger = logging.getLogger("YerelAI.Security")

    def sanitize_sql_like(self, sorgu: str) -> str:
        if not sorgu:
            return ""
        sorgu = sorgu.replace("\\", "\\\\")
        sorgu = sorgu.replace("%", "\\%")
        sorgu = sorgu.replace("_", "\\_")
        return f"%{sorgu}%"

    def validate_input_length(self, text: str, max_length: int = None) -> bool:
        max_len = max_length or self.config.max_input_length
        if len(text) > max_len:
            self.logger.warning(f"Input çok uzun: {len(text)} > {max_len}")
            return False
        return True

    def sanitize_command(self, cmd: str) -> str:
        dangerous_chars = [';', '&', '|', '`', '$', '(', ')', '{', '}', '<', '>', '\n']
        for char in dangerous_chars:
            if char in cmd:
                self.logger.warning(f"Zararlı karakter tespit edildi: {char}")
                raise ValueError(f"Komut içinde izin verilmeyen karakter: {char}")
        return cmd.strip()

    def validate_path(self, path: str, base_dir: Path) -> bool:
        try:
            full_path = (base_dir / path).resolve()
            base_resolved = base_dir.resolve()
            if not str(full_path).startswith(str(base_resolved)):
                self.logger.error(f"Path traversal tespit edildi: {path}")
                return False
            return True
        except Exception as e:
            self.logger.error(f"Path validasyon hatası: {e}")
            return False

    def mask_sensitive_data(self, text: str) -> str:
        patterns = [
            (r'sk-[a-zA-Z0-9]{20,}', 'sk-***'),
            (r'Bearer\s+[a-zA-Z0-9\-_]+', 'Bearer ***'),
            (r'password[=:]\s*\S+', 'password=***'),
        ]
        for pattern, replacement in patterns:
            text = re.sub(pattern, replacement, text, flags=re.IGNORECASE)
        return text

# ==================== VERİTABANI YÖNETİMİ ====================

class DatabaseManager:
    def __init__(self, db_path: Path):
        self.db_path = db_path
        self.lock = threading.RLock()
        self.local = threading.local()
        self.logger = logging.getLogger("YerelAI.Database")
        self._init_database()

    def _get_connection(self) -> sqlite3.Connection:
        if not hasattr(self.local, 'conn') or self.local.conn is None:
            self.local.conn = sqlite3.connect(
                str(self.db_path),
                check_same_thread=False,
                timeout=30.0
            )
            self.local.conn.row_factory = sqlite3.Row
        return self.local.conn

    @contextmanager
    def get_cursor(self):
        with self.lock:
            conn = self._get_connection()
            cursor = conn.cursor()
            try:
                yield cursor
                conn.commit()
            except Exception as e:
                conn.rollback()
                self.logger.error(f"Veritabanı hatası: {e}")
                raise
            finally:
                cursor.close()

    def close(self):
        if hasattr(self.local, 'conn') and self.local.conn:
            self.local.conn.close()
            self.local.conn = None

    def _init_database(self):
        with self.get_cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS kisa_sureli (
                    id TEXT PRIMARY KEY,
                    icerik TEXT NOT NULL,
                    metadata TEXT DEFAULT '{}',
                    erisim_sayisi INTEGER DEFAULT 0,
                    son_erisim TEXT,
                    olusturma TEXT NOT NULL,
                    bitis TEXT NOT NULL
                )
            """)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS uzun_sureli (
                    id TEXT PRIMARY KEY,
                    icerik TEXT NOT NULL,
                    metadata TEXT DEFAULT '{}',
                    etiketler TEXT DEFAULT '[]',
                    onem INTEGER DEFAULT 5 CHECK(onem >= 1 AND onem <= 10),
                    erisim_sayisi INTEGER DEFAULT 0,
                    son_erisim TEXT,
                    olusturma TEXT NOT NULL
                )
            """)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS beyani (
                    id TEXT PRIMARY KEY,
                    icerik TEXT NOT NULL,
                    metadata TEXT DEFAULT '{}',
                    kategori TEXT DEFAULT 'genel',
                    olusturma TEXT NOT NULL
                )
            """)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS episodik (
                    id TEXT PRIMARY KEY,
                    olay TEXT NOT NULL,
                    metadata TEXT DEFAULT '{}',
                    duygu TEXT DEFAULT 'nötr',
                    baglam TEXT DEFAULT '{}',
                    zaman TEXT NOT NULL
                )
            """)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS oturumlar (
                    id TEXT PRIMARY KEY,
                    isim TEXT NOT NULL,
                    proje_yolu TEXT,
                    olusturma TEXT NOT NULL,
                    mod TEXT DEFAULT 'build'
                )
            """)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS mesajlar (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    oturum_id TEXT NOT NULL,
                    rol TEXT NOT NULL CHECK(rol IN ('user', 'assistant', 'system')),
                    icerik TEXT NOT NULL,
                    zaman TEXT NOT NULL,
                    FOREIGN KEY(oturum_id) REFERENCES oturumlar(id) ON DELETE CASCADE
                )
            """)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS gorevler (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    baslik TEXT NOT NULL,
                    aciklama TEXT DEFAULT '',
                    oncelik TEXT DEFAULT 'orta' CHECK(oncelik IN ('düşük', 'orta', 'yüksek', 'acil')),
                    durum TEXT DEFAULT 'bekliyor' CHECK(durum IN ('bekliyor', 'devam', 'tamamlandi', 'iptal')),
                    olusturma TEXT NOT NULL,
                    tamamlanma TEXT
                )
            """)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS ogrenilen (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    soru TEXT NOT NULL UNIQUE,
                    yanit TEXT NOT NULL,
                    olusturma TEXT NOT NULL
                )
            """)
            cur.execute("CREATE INDEX IF NOT EXISTS idx_kisa_bitis ON kisa_sureli(bitis)")
            cur.execute("CREATE INDEX IF NOT EXISTS idx_uzun_onem ON uzun_sureli(onem DESC)")
            cur.execute("CREATE INDEX IF NOT EXISTS idx_mesaj_oturum ON mesajlar(oturum_id)")
            cur.execute("CREATE INDEX IF NOT EXISTS idx_ogrenilen_soru ON ogrenilen(soru)")
            self.logger.info("Veritabanı başlatıldı")

    def kisa_ekle(self, icerik: str, meta: dict = None) -> str:
        id = str(uuid.uuid4())
        now = datetime.datetime.now().isoformat()
        expires = (datetime.datetime.now() + datetime.timedelta(hours=24)).isoformat()
        with self.get_cursor() as cur:
            cur.execute(
                "INSERT INTO kisa_sureli (id, icerik, metadata, son_erisim, olusturma, bitis) VALUES (?, ?, ?, ?, ?, ?)",
                (id, icerik, json.dumps(meta or {}), now, now, expires)
            )
        return id

    def kisa_getir(self, limit: int = 10) -> List[Dict]:
        now = datetime.datetime.now().isoformat()
        with self.get_cursor() as cur:
            cur.execute(
                "SELECT * FROM kisa_sureli WHERE bitis > ? ORDER BY olusturma DESC LIMIT ?",
                (now, limit)
            )
            return [dict(r) for r in cur.fetchall()]

    def kisa_temizle(self):
        now = datetime.datetime.now().isoformat()
        with self.get_cursor() as cur:
            cur.execute("DELETE FROM kisa_sureli WHERE bitis < ?", (now,))
            return cur.rowcount

    def uzun_ekle(self, icerik: str, etiketler: List[str] = None, onem: int = 5, meta: dict = None) -> str:
        if not 1 <= onem <= 10:
            raise ValueError("Önem 1-10 arası olmalı")
        id = str(uuid.uuid4())
        now = datetime.datetime.now().isoformat()
        with self.get_cursor() as cur:
            cur.execute(
                "INSERT INTO uzun_sureli (id, icerik, metadata, etiketler, onem, son_erisim, olusturma) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (id, icerik, json.dumps(meta or {}), json.dumps(etiketler or []), onem, now, now)
            )
        return id

    def uzun_ara(self, sorgu: str, security: SecurityManager) -> List[Dict]:
        safe_query = security.sanitize_sql_like(sorgu)
        with self.get_cursor() as cur:
            cur.execute(
                "SELECT * FROM uzun_sureli WHERE icerik LIKE ? ESCAPE '\\' OR etiketler LIKE ? ESCAPE '\\' ORDER BY onem DESC, olusturma DESC LIMIT 50",
                (safe_query, safe_query)
            )
            return [dict(r) for r in cur.fetchall()]

    def uzun_getir(self, etiketler: List[str] = None, limit: int = 50) -> Generator[Dict, None, None]:
        with self.get_cursor() as cur:
            if etiketler:
                for tag in etiketler:
                    cur.execute(
                        "SELECT * FROM uzun_sureli WHERE etiketler LIKE ? ORDER BY onem DESC LIMIT ?",
                        (f'%"{tag}"%', limit)
                    )
                    for row in cur:
                        yield dict(row)
            else:
                cur.execute("SELECT * FROM uzun_sureli ORDER BY onem DESC, olusturma DESC LIMIT ?", (limit,))
                for row in cur:
                    yield dict(row)

    def beyani_ekle(self, icerik: str, kategori: str = "genel", meta: dict = None) -> str:
        id = str(uuid.uuid4())
        now = datetime.datetime.now().isoformat()
        with self.get_cursor() as cur:
            cur.execute(
                "INSERT INTO beyani (id, icerik, metadata, kategori, olusturma) VALUES (?, ?, ?, ?, ?)",
                (id, icerik, json.dumps(meta or {}), kategori, now)
            )
        return id

    def beyani_getir(self, kategori: str = None) -> List[Dict]:
        with self.get_cursor() as cur:
            if kategori:
                cur.execute("SELECT * FROM beyani WHERE kategori = ? ORDER BY olusturma DESC", (kategori,))
            else:
                cur.execute("SELECT * FROM beyani ORDER BY olusturma DESC")
            return [dict(r) for r in cur.fetchall()]

    def episodik_ekle(self, olay: str, duygu: str = "nötr", baglam: dict = None, meta: dict = None) -> str:
        id = str(uuid.uuid4())
        now = datetime.datetime.now().isoformat()
        with self.get_cursor() as cur:
            cur.execute(
                "INSERT INTO episodik (id, olay, metadata, duygu, baglam, zaman) VALUES (?, ?, ?, ?, ?, ?)",
                (id, olay, json.dumps(meta or {}), duygu, json.dumps(baglam or {}), now)
            )
        return id

    def episodik_getir(self, limit: int = 20) -> List[Dict]:
        with self.get_cursor() as cur:
            cur.execute("SELECT * FROM episodik ORDER BY zaman DESC LIMIT ?", (limit,))
            return [dict(r) for r in cur.fetchall()]

    def oturum_olustur(self, isim: str = None, proje: str = None) -> Dict:
        id = str(uuid.uuid4())[:8]
        now = datetime.datetime.now().isoformat()
        isim = isim or f"oturum-{id}"
        proje = proje or os.getcwd()
        with self.get_cursor() as cur:
            cur.execute(
                "INSERT INTO oturumlar (id, isim, proje_yolu, olusturma, mod) VALUES (?, ?, ?, ?, ?)",
                (id, isim, proje, now, "build")
            )
        return {"id": id, "isim": isim}

    def oturum_listele(self) -> List[Dict]:
        with self.get_cursor() as cur:
            cur.execute("SELECT * FROM oturumlar ORDER BY olusturma DESC")
            return [dict(r) for r in cur.fetchall()]

    def oturum_getir(self, id: str) -> Optional[Dict]:
        with self.get_cursor() as cur:
            cur.execute("SELECT * FROM oturumlar WHERE id = ?", (id,))
            r = cur.fetchone()
            return dict(r) if r else None

    def oturum_mesaj_ekle(self, oid: str, rol: str, icerik: str):
        if rol not in ('user', 'assistant', 'system'):
            raise ValueError("Rol user/assistant/system olmalı")
        now = datetime.datetime.now().isoformat()
        with self.get_cursor() as cur:
            cur.execute(
                "INSERT INTO mesajlar (oturum_id, rol, icerik, zaman) VALUES (?, ?, ?, ?)",
                (oid, rol, icerik, now)
            )

    def oturum_mesajlari(self, oid: str, limit: int = 100) -> List[Dict]:
        with self.get_cursor() as cur:
            cur.execute(
                "SELECT * FROM mesajlar WHERE oturum_id = ? ORDER BY zaman DESC LIMIT ?",
                (oid, limit)
            )
            return [dict(r) for r in cur.fetchall()]

    def gorev_ekle(self, baslik: str, aciklama: str = "", oncelik: str = "orta") -> int:
        now = datetime.datetime.now().isoformat()
        with self.get_cursor() as cur:
            cur.execute(
                "INSERT INTO gorevler (baslik, aciklama, oncelik, durum, olusturma) VALUES (?, ?, ?, ?, ?)",
                (baslik, aciklama, oncelik, "bekliyor", now)
            )
            return cur.lastrowid

    def gorev_listele(self, durum: str = None) -> List[Dict]:
        with self.get_cursor() as cur:
            if durum:
                cur.execute("SELECT * FROM gorevler WHERE durum = ? ORDER BY olusturma DESC", (durum,))
            else:
                cur.execute("SELECT * FROM gorevler ORDER BY olusturma DESC")
            return [dict(r) for r in cur.fetchall()]

    def gorev_tamamla(self, id: int):
        now = datetime.datetime.now().isoformat()
        with self.get_cursor() as cur:
            cur.execute(
                "UPDATE gorevler SET durum='tamamlandi', tamamlanma=? WHERE id=?",
                (now, id)
            )

    def gorev_sil(self, id: int):
        with self.get_cursor() as cur:
            cur.execute("DELETE FROM gorevler WHERE id=?", (id,))

    def ogren(self, soru: str, yanit: str) -> bool:
        now = datetime.datetime.now().isoformat()
        try:
            with self.get_cursor() as cur:
                cur.execute(
                    "INSERT OR REPLACE INTO ogrenilen (soru, yanit, olusturma) VALUES (?, ?, ?)",
                    (soru.lower().strip(), yanit, now)
                )
            return True
        except Exception as e:
            self.logger.error(f"Öğrenme hatası: {e}")
            return False

    def ogrenilen_ara(self, sorgu: str) -> List[Dict]:
        with self.get_cursor() as cur:
            cur.execute(
                "SELECT * FROM ogrenilen WHERE soru LIKE ? ORDER BY olusturma DESC LIMIT 5",
                (f"%{sorgu.lower()}%",)
            )
            return [dict(r) for r in cur.fetchall()]

    def ogrenilen_listele(self, limit: int = 50) -> List[Dict]:
        with self.get_cursor() as cur:
            cur.execute("SELECT * FROM ogrenilen ORDER BY olusturma DESC LIMIT ?", (limit,))
            return [dict(r) for r in cur.fetchall()]

    def istatistik(self) -> Dict:
        with self.get_cursor() as cur:
            return {
                "kisa": cur.execute("SELECT COUNT(*) FROM kisa_sureli").fetchone()[0],
                "uzun": cur.execute("SELECT COUNT(*) FROM uzun_sureli").fetchone()[0],
                "beyani": cur.execute("SELECT COUNT(*) FROM beyani").fetchone()[0],
                "episodik": cur.execute("SELECT COUNT(*) FROM episodik").fetchone()[0],
                "oturum": cur.execute("SELECT COUNT(*) FROM oturumlar").fetchone()[0],
                "gorev": cur.execute("SELECT COUNT(*) FROM gorevler").fetchone()[0],
                "gorev_bekliyor": cur.execute("SELECT COUNT(*) FROM gorevler WHERE durum='bekliyor'").fetchone()[0],
                "ogrenilen": cur.execute("SELECT COUNT(*) FROM ogrenilen").fetchone()[0]
            }

# ==================== AI YÖNETİMİ ====================

class AIManager:
    def __init__(self, config: Config):
        self.config = config
        self.logger = logging.getLogger("YerelAI.AI")

    def sorgula(self, prompt: str, system_prompt: str = None, context: List[Dict] = None) -> str:
        try:
            if self.config.ai_provider == "ollama":
                return self._ollama_sorgula(prompt, system_prompt, context)
            elif self.config.ai_provider == "openai":
                return self._openai_sorgula(prompt, system_prompt, context)
            else:
                return f"Bilinmeyen AI sağlayıcı: {self.config.ai_provider}"
        except Exception as e:
            self.logger.error(f"AI sorgu hatası: {e}")
            return f"AI hatası: {str(e)}"

    def _ollama_sorgula(self, prompt: str, system_prompt: str = None, context: List[Dict] = None) -> str:
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        if context:
            for msg in context[-10:]:
                messages.append({"role": msg.get("rol", "user"), "content": msg.get("icerik", "")})
        messages.append({"role": "user", "content": prompt})

        data = {
            "model": self.config.ai_model,
            "messages": messages,
            "stream": False,
            "options": {"temperature": 0.7}
        }

        req = urllib.request.Request(
            self.config.ai_api_url,
            data=json.dumps(data).encode('utf-8'),
            headers={'Content-Type': 'application/json'},
            method='POST'
        )

        try:
            with urllib.request.urlopen(req, timeout=self.config.ai_timeout) as resp:
                sonuc = json.loads(resp.read().decode('utf-8'))
                return sonuc.get('message', {}).get('content', 'Yanıt yok')
        except urllib.error.URLError as e:
            self.logger.error(f"Ollama bağlantı hatası: {e}")
            return "Ollama çalışmıyor. 'ollama serve' komutuyla başlatabilirsiniz."
        except json.JSONDecodeError as e:
            self.logger.error(f"JSON parse hatası: {e}")
            return "AI yanıtı işlenemedi (geçersiz JSON)"

    def _openai_sorgula(self, prompt: str, system_prompt: str = None, context: List[Dict] = None) -> str:
        if not self.config.openai_api_key:
            return "OpenAI API key yok! OPENAI_API_KEY ortam değişkenini ayarlayın."

        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        if context:
            for msg in context[-10:]:
                messages.append({"role": msg.get("rol", "user"), "content": msg.get("icerik", "")})
        messages.append({"role": "user", "content": prompt})

        data = {"model": "gpt-3.5-turbo", "messages": messages, "temperature": 0.7}

        req = urllib.request.Request(
            "https://api.openai.com/v1/chat/completions",
            data=json.dumps(data).encode('utf-8'),
            headers={'Content-Type': 'application/json', 'Authorization': f'Bearer {self.config.openai_api_key}'},
            method='POST'
        )

        try:
            with urllib.request.urlopen(req, timeout=self.config.ai_timeout) as resp:
                sonuc = json.loads(resp.read().decode('utf-8'))
                return sonuc['choices'][0]['message']['content']
        except urllib.error.HTTPError as e:
            self.logger.error(f"OpenAI HTTP hatası: {e.code}")
            return f"OpenAI API hatası: {e.code}"
        except json.JSONDecodeError as e:
            self.logger.error(f"JSON parse hatası: {e}")
            return "AI yanıtı işlenemedi"

    def kontrol(self) -> bool:
        try:
            if self.config.ai_provider == "ollama":
                req = urllib.request.Request("http://localhost:11434/api/tags")
                with urllib.request.urlopen(req, timeout=5) as resp:
                    return resp.status == 200
            return True
        except:
            return False

# ==================== KOMUT YÖNETİMİ ====================

class CommandManager:
    def __init__(self, config: Config, security: SecurityManager):
        self.config = config
        self.security = security
        self.logger = logging.getLogger("YerelAI.Command")

    def powershell(self, cmd: str) -> str:
        try:
            cmd = self.security.sanitize_command(cmd)
            result = subprocess.run(
                ["powershell", "-Command", cmd],
                capture_output=True, text=True, timeout=self.config.ps_timeout,
                encoding='utf-8', errors='replace'
            )
            output = result.stdout.strip() if result.stdout else ""
            error = result.stderr.strip() if result.stderr else ""
            if result.returncode != 0:
                return f"Hata (kod {result.returncode}): {error[:200]}"
            return output[:2000]
        except subprocess.TimeoutExpired:
            return f"Hata: Zaman aşımı ({self.config.ps_timeout}s)"
        except ValueError as e:
            return f"Güvenlik hatası: {e}"
        except Exception as e:
            return f"Hata: {str(e)}"

    def opencode(self, komut: str, config) -> str:
        try:
            cmd_clean = self.security.sanitize_command(komut)
            data_dir = Path.home() / ".yerel_asistan"
            data_dir.mkdir(parents=True, exist_ok=True)
            if not self.security.validate_path("oc_cmd_safe.txt", data_dir):
                return "Hata: Geçersiz dosya yolu"
            result = subprocess.run(
                [config.opencode_cli_path, "--yes"], input=cmd_clean + "\n",
                capture_output=True, text=True, timeout=config.opencode_timeout,
                encoding='utf-8', errors='replace'
            )
            output = result.stdout + result.stderr
            return output[:1500] if output else "Sonuç yok"
        except subprocess.TimeoutExpired:
            return f"Hata: OpenCode zaman aşımı ({config.opencode_timeout}s)"
        except ValueError as e:
            return f"Güvenlik hatası: {e}"
        except Exception as e:
            return f"OpenCode hatası: {str(e)}"

# ==================== ANA ASİSTAN SINIFI ====================

class YerelAIAsistan:
    def __init__(self, data_dir: str = None):
        self.config_manager = ConfigManager(data_dir)
        self.config = self.config_manager.get()
        self.data_dir = Path(data_dir) if data_dir else Path.home() / ".yerel_asistan"
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.logger = setup_logging(self.data_dir)
        self.security = SecurityManager(self.config)
        db_path = self.data_dir / self.config.db_name
        self.db = DatabaseManager(db_path)
        self.ai = AIManager(self.config)
        self.cmd = CommandManager(self.config, self.security)
        self.oturum = None
        self.running = True
        self._baslat()

    def _baslat(self):
        print("\n" + "="*60)
        print("YEREL AI ASISTAN v4.3 - GÜVENLI & STABİL")
        print("="*60)
        print(f"DB: {self.data_dir / self.config.db_name}")
        print(f"AI: {self.config.ai_provider} ({self.config.ai_model})")
        if self.ai.kontrol():
            print("AI Servisi: ✅ Bağlı")
        else:
            print("AI Servisi: ⚠️ Bağlı değil")
        temizlenen = self.db.kisa_temizle()
        if temizlenen > 0:
            self.logger.info(f"{temizlenen} eski kayıt temizlendi")

    def yardim(self) -> str:
        return """
╔══════════════════════════════════════════════════════════╗
║                    KOMUT REHBERİ v4.3                     ║
╠══════════════════════════════════════════════════════════╣
║ ÖĞRENME: ogret <soru> - <yanıt>                          ║
║ HAFIZA: hafiza-ekle, hafiza-ara, hafiza-durum            ║
║ OTURUM: oturum, oturum-liste, oturum-gecmis              ║
║ GÖREV: gorev ekle/liste/tamamla/sil                      ║
║ SİSTEM: ai <soru>, ps <komut>, oc <komut>, stat, q       ║
╚══════════════════════════════════════════════════════════╝"""

    def ai_cevapla(self, soru: str) -> str:
        try:
            ogrenilen = self.db.ogrenilen_ara(soru)
            if ogrenilen:
                return f"[Öğrenilen] {ogrenilen[0]['yanit']}"
            hafiza_list = list(self.db.uzun_getir(limit=5))
            hafiza_metin = "\n".join([f"- {h['icerik'][:100]}" for h in hafiza_list])
            context = []
            if self.oturum:
                context = self.db.oturum_mesajlari(self.oturum, limit=5)
            system_prompt = f"""Sen yardımcı bir AI asistansın. 
Kullanıcıya kısa ve faydalı yanıtlar ver.
Hafızadaki bilgiler: {hafiza_metin}"""
            yanit = self.ai.sorgula(soru, system_prompt, context)
            if self.oturum:
                self.db.oturum_mesaj_ekle(self.oturum, "user", soru[:500])
                self.db.oturum_mesaj_ekle(self.oturum, "assistant", yanit[:500])
            return yanit
        except Exception as e:
            return f"Yanıt oluşturulamadı: {str(e)}"

    def calistir(self):
        print(self.yardim())
        while self.running:
            try:
                prompt = f"\n[AI:{self.oturum or 'yeni'}]> "
                cmd = input(prompt).strip()
                if not cmd:
                    continue
                if not self.security.validate_input_length(cmd):
                    print("❌ Hata: Input çok uzun")
                    continue
                self._komut_isle(cmd)
            except KeyboardInterrupt:
                print("\n👋 Görüşürüz!")
                self.kapat()
                break
            except EOFError:
                self.kapat()
                break

    def _komut_isle(self, cmd: str):
        cmd_lower = cmd.lower()
        if cmd_lower in ["q", "exit", "quit"]:
            print("👋 Görüşürüz!")
            self.running = False
            self.kapat()
            return
        if cmd_lower in ["?", "yardim", "help"]:
            print(self.yardim())
            return
        if cmd_lower == "temiz":
            print("\n" * 50)
            return
        if cmd_lower == "stat":
            s = self.db.istatistik()
            print(f"📊 {s['kisa']} kısa, {s['uzun']} uzun, {s['ogrenilen']} öğrenildi")
            return
        if cmd_lower == "config":
            print(f"⚙️ AI: {self.config.ai_provider} ({self.config.ai_model})")
            return
        if cmd_lower == "hafiza-durum":
            s = self.db.istatistik()
            print(f"🧠 {s['kisa']} kısa, {s['uzun']} uzun, {s['beyani']} beyani")
            return
        if cmd_lower.startswith("hafiza-ekle "):
            icerik = cmd[12:]
            if self.security.validate_input_length(icerik):
                self.db.uzun_ekle(icerik)
                print("✅ Hafızaya eklendi")
            return
        if cmd_lower.startswith("hafiza-kisa "):
            icerik = cmd[12:]
            if self.security.validate_input_length(icerik):
                self.db.kisa_ekle(icerik)
                print("✅ Kısa hafızaya eklendi (24s)")
            return
        if cmd_lower.startswith("hafiza-ara "):
            sorgu = cmd[11:]
            try:
                sonuclar = self.db.uzun_ara(sorgu, self.security)
                print(f"🔍 {len(sonuclar)} sonuç:")
                for r in sonuclar[:10]:
                    print(f"  [{r['onem']}] {r['icerik'][:80]}...")
            except Exception as e:
                print(f"❌ {e}")
            return
        if cmd_lower.startswith("ogret "):
            parcalar = cmd[6:].split(" - ", 1)
            if len(parcalar) == 2:
                soru, yanit = parcalar[0].strip(), parcalar[1].strip()
                if self.db.ogren(soru, yanit):
                    print(f"✅ Öğrendim: '{soru}'")
            else:
                parcalar2 = cmd[6:].split(" = ", 1)
                if len(parcalar2) == 2:
                    soru, yanit = parcalar2[0].strip(), parcalar2[1].strip()
                    if self.db.ogren(soru, yanit):
                        print(f"✅ Öğrendim: '{soru}'")
            return
        if cmd_lower in ["ogrenilen", "ne ogrendin"]:
            liste = self.db.ogrenilen_listele(limit=15)
            print("📚 Öğrendiklerim:")
            for o in liste:
                print(f"  • {o['soru']} = {o['yanit']}")
            return
        if cmd_lower == "oturum":
            o = self.db.oturum_olustur()
            self.oturum = o['id']
            print(f"✅ Oturum: {o['id']}")
            return
        if cmd_lower.startswith("oturum ") and len(cmd) > 7:
            oid = cmd[7:].strip()
            o = self.db.oturum_getir(oid)
            if o:
                self.oturum = oid
                print(f"✅ Geçildi: {o['isim']}")
            else:
                print("❌ Oturum bulunamadı")
            return
        if cmd_lower == "oturum-liste":
            oturumlar = self.db.oturum_listele()
            print("📁 Oturumlar:")
            for o in oturumlar[:10]:
                aktif = "👉" if o['id'] == self.oturum else "  "
                print(f"{aktif} {o['id']} | {o['isim']}")
            return
        if cmd_lower == "oturum-gecmis":
            if self.oturum:
                mesajlar = self.db.oturum_mesajlari(self.oturum, limit=10)
                for m in reversed(mesajlar):
                    rol_emoji = "👤" if m['rol'] == 'user' else "🤖"
                    print(f"{rol_emoji} {m['icerik'][:60]}...")
            else:
                print("⚠️ Aktif oturum yok")
            return
        if cmd_lower.startswith("gorev "):
            parca = cmd[6:].split(None, 1)
            eylem = parca[0] if parca else ""
            arg = parca[1] if len(parca) > 1 else ""
            if eylem == "ekle" and arg:
                sid = self.db.gorev_ekle(arg)
                print(f"✅ Görev eklendi (#{sid})")
            elif eylem in ["liste", "list"]:
                gorevler = self.db.gorev_listele()
                for g in gorevler:
                    durum_emoji = "✅" if g['durum'] == "tamamlandi" else "⏳"
                    print(f"{durum_emoji} #{g['id']} [{g['oncelik']}] {g['baslik']}")
            elif eylem == "tamamla" and arg.isdigit():
                self.db.gorev_tamamla(int(arg))
                print("✅ Tamamlandı")
            elif eylem == "sil" and arg.isdigit():
                self.db.gorev_sil(int(arg))
                print("✅ Silindi")
            return
        if cmd_lower.startswith("ps "):
            komut = cmd[3:]
            print(f"⚡ {komut}")
            sonuc = self.cmd.powershell(komut)
            print(sonuc[:1000])
            return
        if cmd_lower.startswith("oc ") or cmd_lower.startswith("opencode "):
            k = cmd.split(" ", 1)[1] if " " in cmd else ""
            print("🔧 OpenCode...")
            sonuc = self.cmd.opencode(k, self.config)
            print(sonuc[:1500])
            return
        if cmd_lower.startswith("ai "):
            soru = cmd[3:]
            print("🤖 AI düşünüyor...")
            yanit = self.ai_cevapla(soru)
            print(f"\n{yanit}")
            return
        print("🤖 AI düşünüyor...")
        yanit = self.ai_cevapla(cmd)
        print(f"\n{yanit}")

    def kapat(self):
        try:
            self.logger.info("Kapatılıyor...")
            self.db.close()
            print("💾 Kapatıldı")
        except Exception as e:
            self.logger.error(f"Kapatma hatası: {e}")

# ==================== FLASK API ====================

from flask import Flask, jsonify, request
import logging
import json

app = Flask(__name__)
app.config['JSON_AS_ASCII'] = False
app.config['JSON_SORT_KEYS'] = False
logging.getLogger('werkzeug').setLevel(logging.ERROR)

# Custom JSON encoder for UTF-8
class CustomJSONProvider(app.json_provider_class):
    def dumps(self, obj, **kwargs):
        return json.dumps(obj, ensure_ascii=False, **kwargs)
    def loads(self, s, **kwargs):
        return json.loads(s, **kwargs)

app.json_provider_class = CustomJSONProvider
app.json = CustomJSONProvider(app)

asistan = None

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "v": "4.3"})

@app.route("/ai", methods=["POST"])
def ai():
    data = request.json or {}
    soru = data.get("message", "")
    if not soru:
        return jsonify({"error": "message gerekli"}), 400
    yanit = asistan.ai_cevapla(soru)
    return jsonify({"response": yanit})

@app.route("/hafiza/ekle", methods=["POST"])
def hafiza_ekle():
    data = request.json or {}
    icerik = data.get("icerik", "")
    tur = data.get("tur", "uzun")  # uzun veya kisa
    if not icerik:
        return jsonify({"error": "icerik gerekli"}), 400
    if tur == "kisa":
        asistan.db.kisa_ekle(icerik)
    else:
        asistan.db.uzun_ekle(icerik)
    return jsonify({"status": "ok"})

@app.route("/hafiza/ara", methods=["GET"])
def hafiza_ara():
    sorgu = request.args.get("q", "")
    if not sorgu:
        return jsonify({"error": "q parametresi gerekli"}), 400
    sonuclar = asistan.db.uzun_ara(sorgu, asistan.security)
    return jsonify({"results": sonuclar})

@app.route("/hafiza/durum", methods=["GET"])
def hafiza_durum():
    s = asistan.db.istatistik()
    return jsonify(s)

@app.route("/ogret", methods=["POST"])
def ogret():
    data = request.json or {}
    soru = data.get("soru", "")
    yanit = data.get("yanit", "")
    if not soru or not yanit:
        return jsonify({"error": "soru ve yanit gerekli"}), 400
    asistan.db.ogren(soru, yanit)
    return jsonify({"status": "ok"})

@app.route("/gorev/ekle", methods=["POST"])
def gorev_ekle():
    data = request.json or {}
    baslik = data.get("baslik", "")
    if not baslik:
        return jsonify({"error": "baslik gerekli"}), 400
    sid = asistan.db.gorev_ekle(baslik)
    return jsonify({"id": sid})

@app.route("/gorev/liste", methods=["GET"])
def gorev_liste():
    gorevler = asistan.db.gorev_listele()
    return jsonify({"gorevler": gorevler})

@app.route("/gorev/tamamla/<int:id>", methods=["POST"])
def gorev_tamamla(id):
    asistan.db.gorev_tamamla(id)
    return jsonify({"status": "ok"})

@app.route("/oturum/olustur", methods=["POST"])
def oturum_olustur():
    o = asistan.db.oturum_olustur()
    asistan.oturum = o['id']
    return jsonify(o)

@app.route("/oturum/lista", methods=["GET"])
def oturum_liste():
    oturumlar = asistan.db.oturum_listele()
    return jsonify({"oturumlar": oturumlar})

@app.route("/istatistik", methods=["GET"])
def istatistik():
    return jsonify(asistan.db.istatistik())

# ==================== GİRİŞ NOKTASI ====================

if __name__ == "__main__":
    import sys
    # API modu veya interaktif mod
    if len(sys.argv) > 1 and sys.argv[1] == "--api":
        # API modu
        data_dir = sys.argv[2] if len(sys.argv) > 2 else None
        asistan = YerelAIAsistan(data_dir)
        port = int(sys.argv[3]) if len(sys.argv) > 3 else 5000
        print(f"🚀 API başlatıldı: http://localhost:{port}")
        app.run(host="0.0.0.0", port=port)
    else:
        # Interaktif mod
        asistan = YerelAIAsistan()
        asistan.calistir()
