# 07 — MQL5 Compile Gate

**เจ้าของ:** Claude · **เริ่มใช้:** 2026-07-26 · **สคริปต์:** [`tools/compile-gate.ps1`](../tools/compile-gate.ps1)

Codex ไม่มี MetaEditor (ยืนยันจาก [gap audit G3](06-gap-audit.md)) ดังนั้น MQL5 ทุกไฟล์
ต้องผ่าน gate นี้ก่อนถือว่าเสร็จ Claude เป็นคนรัน

---

## รันอย่างไร

```powershell
powershell -ExecutionPolicy Bypass -File D:\ea-farm\tools\compile-gate.ps1
```

exit 0 = ผ่าน · exit 1 = มี error · exit 2 = ไม่พบ MetaEditor
ผลลัพธ์เขียนลง `%TEMP%\ea-farm-compile\gate-<timestamp>.txt` ด้วย

## คำสั่งดิบ (ถ้าต้องรันไฟล์เดียว)

```powershell
& "C:\Program Files\MetaTrader 5\metaeditor64.exe" `
    /compile:D:\ea-farm\mt5-ea\Experts\FarmExecutor.mq5 `
    /inc:D:\ea-farm\mt5-ea `
    /log:C:\Temp\out.log
Get-Content C:\Temp\out.log -Encoding Unicode
```

| ข้อควรรู้ | รายละเอียด |
|-----------|-----------|
| `/inc:` ชี้ที่ไหน | ต้องเป็น **root ที่มีโฟลเดอร์ `Include/` อยู่ข้างใน** → `D:\ea-farm\mt5-ea` ทำให้ `#include <Farm/Wire.mqh>` resolve เป็น `mt5-ea\Include\Farm\Wire.mqh` |
| log encoding | **UTF-16LE** — ต้องอ่านด้วย `-Encoding Unicode` ไม่ใช่ utf8 ไม่งั้นได้ขยะ |
| exit code | metaeditor คืน `1` แม้ compile สำเร็จ — **ห้ามใช้ exit code ตัดสิน** ต้อง parse บรรทัด `Result:` ในไฟล์ log |
| `.mqh` เดี่ยวๆ | คอมไพล์ไม่ได้ — script จึงเช็คว่าทุก `.mqh` ถูก `include` จาก target อย่างน้อย 1 ตัว ไม่งั้นมันจะไม่เคยผ่าน compiler เลยแบบเงียบๆ |
| ต้องเปิด MT5 terminal ไหม | ไม่ต้อง — MetaEditor คอมไพล์แบบ standalone ได้ |

## เพิ่ม target ใหม่

แก้ array `$Targets` ใน `tools/compile-gate.ps1` — ทุกไฟล์ `.mq5` ใหม่ที่ Codex เขียน
ต้องเพิ่มเข้าที่นี่ ไม่งั้น gate จะไม่ตรวจ

---

---

## ✅ รัน test อัตโนมัติได้แล้ว (2026-07-27)

```powershell
powershell -ExecutionPolicy Bypass -File D:\ea-farm\tools\run-mql5-tests.ps1
```

deploy → compile → Strategy Tester → parse JSON → เทียบ `git_sha` กับ HEAD ในคำสั่งเดียว
พิสูจน์ครบทุกขั้นด้วย `tools/probe/TesterProbe.mq5` (รันจบ 8 วินาที)

### สภาพแวดล้อมที่ใช้ได้จริง — ตรวจแล้ว

| หัวข้อ | ค่า | ทำไมสำคัญ |
|--------|-----|-----------|
| Terminal สำหรับ **compile** | `C:\Program Files\MetaTrader 5\metaeditor64.exe` | คอมไพล์ไม่ต้องมีบัญชี |
| Terminal สำหรับ **รัน test** | `C:\Program Files\IUX Markets MT5 Terminal3\terminal64.exe` | ★ Strategy Tester **ต้องมีบัญชี+history** และมีแค่ตัวนี้ที่มี (`IUXMarkets-Demo`) — data folder ของ `MetaTrader 5` มีแต่ log เปล่า |
| Data folder | `…\Terminal\A45801173FBAFA01B9AFF0EEDE7938E3` | ที่วาง EA + Include + `.set` |
| Symbol | `EURUSD.iux` | ★ มี suffix `.iux` ใส่ `EURUSD` เปล่าๆ tester abort |
| ช่วง history | 2025.01.01 – 2026.06.19 (H1) | ★ วันที่นอกช่วงนี้ tester abort |
| ผลลัพธ์ | `…\Terminal\Common\Files\ea-farm-<suite>-result.json` | `FILE_COMMON` |

### 5 กับดักที่เสียเวลาไปแล้ว — อย่าทำซ้ำ

1. **`.set` ค่า string ต้องเป็น `Name=value` เปล่าๆ** — suffix `||||N` (ที่ใช้กับ numeric
   param ตอน optimize) จะกลายเป็น**ส่วนหนึ่งของ string** → เจอ `FileOpen err=5004`
   เพราะชื่อไฟล์กลายเป็น `result.json||||N`
2. **★ EA ที่เรียก `ExpertRemove()` ใน `OnInit` → tester log ว่า `tester stopped because
   OnInit failed` และ terminal exit code = 0** ทั้งที่ test รันสำเร็จทุกตัว
   → **ห้ามตัดสินผลจาก exit code เด็ดขาด อ่านไฟล์ JSON อย่างเดียว**
3. **`FILE_UTF8` ไม่มีใน MQL5** — ต้อง `FILE_BIN` + `StringToCharArray(..., CP_UTF8)`
   ดูตัวอย่างที่รันได้จริงใน `tools/probe/TesterProbe.mq5`
4. **ต้อง copy `Include\Farm` เข้า data folder ก่อน** — `#include <Farm/...>` ใน data folder
   ไม่เห็นไฟล์ใน repo
5. **ไฟล์ผลอาจเป็นของรอบเก่า** — runner เช็ค mtime + `git_sha` ว่าตรง HEAD ทั้งคู่
   ไม่งั้นจะอ่านผลเก่าแล้วนึกว่าเขียว

---

## ⚠️ ข้อจำกัดเดิม (แก้แล้ว — เก็บไว้เป็นบันทึก): รัน test แบบ headless ไม่ได้

`tests/mql5/TestWire.mq5` เป็น **Script** (`OnStart()`) และ **MT5 รัน Script แบบ
command-line ไม่ได้** — ต้องลากลงชาร์ตด้วยมือเท่านั้น

Strategy Tester (`terminal64.exe /config:tester.ini`) รันได้เฉพาะ **EA** และ indicator

### ผลกระทบ

gate ตอนนี้ยืนยันได้แค่ว่า **"คอมไพล์ผ่าน"** ยังยืนยันไม่ได้ว่า **"test ผ่าน"**
ซึ่งเป็นสองเรื่องต่างกันมาก โค้ดที่คอมไพล์ผ่านอาจ logic ผิดทั้งหมด

### ทางแก้ที่ต้องใส่ใน SPEC-065

MQL5 test ต้องเป็น **EA ไม่ใช่ Script**:

```mql5
// ❌ ตอนนี้ — รัน headless ไม่ได้
void OnStart() { run_all_tests(); }

// ✅ ที่ต้องเป็น — Strategy Tester รันได้
int OnInit() {
   int failed = run_all_tests();
   WriteJsonResult(failed);        // เขียนผลลง Common\Files\ ให้ CI/คน อ่าน
   ExpertRemove();                 // จบทันที ไม่ต้องรอ tick
   return INIT_SUCCEEDED;
}
```

แล้ว gate จะเพิ่มขั้น:
```powershell
& terminal64.exe /config:tools\tester-tests.ini   # รัน EA test ใน Strategy Tester
# อ่านไฟล์ JSON ผลลัพธ์ → fail ถ้ามี test แดง
```

**เงื่อนไขบังคับใน SPEC-065:** test ต้องเขียนผลเป็น **JSON ลงไฟล์** พร้อม
`git rev-parse HEAD` ของโค้ดที่ทดสอบ เพื่อให้ CI ตรวจได้ว่าผลล่าสุดเขียว
**และตรงกับโค้ดปัจจุบัน** (ไม่ใช่ผลเก่าที่ค้างอยู่)

---

## บทเรียนจากการตั้ง gate ครั้งแรก

| เรื่อง | สิ่งที่เจอ |
|-------|-----------|
| `.ps1` encoding | Windows PowerShell 5.1 อ่าน `.ps1` เป็น **ANSI** ถ้าไม่มี UTF-8 BOM → คอมเมนต์ภาษาไทยทำ parser พัง **สคริปต์ใน `tools/` ต้องเป็น ASCII ล้วน** |
| `.gitattributes` | `*.ps1` ตั้งเป็น `eol=crlf` แล้ว ถูกต้องสำหรับ Windows |
| `.ex5` | อยู่ใน `.gitignore` แล้ว — ไม่ commit binary |
