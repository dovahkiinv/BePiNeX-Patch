# PROMPT PRZEKLEJANY DO NOWEJ ROZMOWY — BepInEx BE / CarX Drift Racing Online 2

> Skopiuj wszystko poniżej poziomej linii i wklej jako pierwszą wiadomość.

---

## Zadanie

Diagnozuję, dlaczego **BepInEx 6 Bleeding Edge (Unity IL2CPP)** przestał działać w grze
**CarX Drift Racing Online 2** (Steam appid **1826420**) po aktualizacji gry **0.20.0 → 0.20.1**.
Będziemy to ciągnąć przez wiele wiadomości — traktuj poniższe ustalenia jako stan faktyczny
i nie wyprowadzaj ich od nowa, chyba że coś się zdezaktualizuje (wtedy sprawdź i popraw).

**Odpowiadaj po polsku.** Nie zgaduj: każde twierdzenie o plikach, wersjach, URL‑ach i API
musi pochodzić z wywołania narzędzia w bieżącej rozmowie. Czego nie sprawdziłeś — oznacz
wprost jako niesprawdzone.

## Ustalony stan (zweryfikowane 2026‑10‑02)

- Gra: **CarX Drift Racing Online 2**, Steam 1826420, Unity, wydane 2026‑05‑07.
  Ostatni changenumber 39426542, rekord odświeżony 2026‑10‑02 15:08 UTC.
- Gra jest **IL2CPP** i jest **modowalna zawsze** (nie wymaga gałęzi beta „moddable").
- **Objaw:** pliki BepInEx są na miejscu (`winhttp.dll`, `doorstop_config.ini`, `dotnet\`, `BepInEx\`),
  ale **nie tworzy się `BepInEx\LogOutput.log`**, czyli BepInEx w ogóle nie startuje.
  ⇒ To problem **bootu/Doorstop**, NIE interop/Cpp2IL/metadata. Czekanie na nowy build nic nie da.
- Użytkownik jest na Windows, Steam, x64 (do potwierdzenia: czy `.exe` gry jest x64).

## Fakty techniczne (sprawdzone narzędziami)

- **`builds.bepis.com` nie istnieje** — domena wystawiona na sprzedaż na HugeDomains.
  Nowy adres BepisBuilds: **https://builds.bepinex.dev/projects/bepinex_be** (HTTP 200).
- Najnowszy build BE: **`6.0.0-be.788+5b766a3`**, data buildu **2026‑09‑01**. Linki prosto do zipa (HTTP 200):
  - x64, 34 336 405 B: `https://builds.bepinex.dev/projects/bepinex_be/788/BepInEx-Unity.IL2CPP-win-x64-6.0.0-be.788%2B5b766a3.zip`
  - x86, 31 440 336 B: `https://builds.bepinex.dev/projects/bepinex_be/788/BepInEx-Unity.IL2CPP-win-x86-6.0.0-be.788%2B5b766a3.zip`
- Zawartość paczki IL2CPP win‑x64 (poziom 0): `BepInEx\`, `dotnet\`, `changelog.txt`,
  `doorstop_config.ini`, `winhttp.dll`, `.doorstop_version`. `BepInEx\core\` ma **37 plików**.
- `.doorstop_version` w be.788 = **4.5.0**. `winhttp.dll` z tej paczki = **26 112 B**,
  nagłówek PE machine **0x8664** (x64).
- `doorstop_config.ini` (be.788): `target_assembly = BepInEx\core\BepInEx.Unity.IL2CPP.dll`,
  `coreclr_path = dotnet\coreclr.dll`, `corlib_dir = dotnet`.
- **BepInEx be.788 ma `LibCpp2IL.dll` = Cpp2IL `2022.1.0-development.1452` → „We support 23‑106".**
  (string wyciągnięty z binarki; w `BepInEx.Unity.IL2CPP.csproj` na masterze jest
  `Samboy063.Cpp2IL.Core 2022.1.0-development.1452` i `Il2CppInterop 1.5.3`.)
- **Cpp2IL `development` = `2022.1.0-development.1743` → „We support 23‑108"** (build 2026‑09‑12).
  Wsparcie v107/v108 weszło commit `01c17484` (2026‑07‑19), czyli PO tym, jak BepInEx cofnął
  Cpp2IL commit `6abdba47` (2026‑06‑28, „Revert Cpp2IL back to development.1452 because of regressions").
- Feed dev Cpp2IL: `https://nuget.samboy.dev/v3/package/samboy063.libcpp2il/2022.1.0-development.1743/samboy063.libcpp2il.2022.1.0-development.1743.nupkg`
  → w środku `lib/net6.0/LibCpp2IL.dll` (ma target net6.0; zależy od `WasmDisassembler 1743` + `AssetRipper.Primitives 3.2.0`,
  a BepInEx be.788 już ma 3.2.0). `Cpp2IL.Core 1743` wymaga `AsmResolver.DotNet 6.0.1` i **nie ma** targetu net6.0.
- Base libraries Unity: **https://unity.bepinex.dev/libraries/** (1579 plików; są m.in. `6000.5.1`…`6000.5.11`,
  `6000.6.0`…`6000.6.4`, `6000.7.0a1`…`6000.7.0b2`). Config: `[IL2CPP] UnityBaseLibrariesSource`.
- Mechanika BepInEx (`Il2CppInteropManager.cs`, master): hash z `GameAssembly.dll` + `unity-libs`
  + wersji Il2CppInterop/Cpp2IL zapisany w `BepInEx/interop/assembly-hash.txt`;
  po zmianie interop **regeneruje się sam**. Klucze config: `UpdateInteropAssemblies`,
  `UnityBaseLibrariesSource`, `GlobalMetadataPath` (domyślnie `{GameDataPath}/il2cpp_data/Metadata/global-metadata.dat`),
  `IL2CPPInteropAssembliesPath`, `DumpDummyAssemblies`, `PreloadIL2CPPInteropAssemblies`.
- Wersja metadata IL2CPP = bajty 5‑8 pliku `global-metadata.dat` (little‑endian int32), magic to bajty 1‑4 (`AF 1B B1 FA`).

## Hipotezy — w tej kolejności (objaw: brak `LogOutput.log`)

1. **Zmieszana instalacja Mono + IL2CPP** — jeśli w `BepInEx\core\` jest `BepInEx.dll` lub `BepInEx.Mono.dll`
   obok `BepInEx.Unity.IL2CPP.dll`. Bardzo prawdopodobne w CarX, bo „jedynka" chodziła na BepInEx 5.x (Mono).
2. **Bitowość** — gra x86 + `winhttp.dll` x64 ⇒ proxy się nie ładuje, zero logów.
3. **EXE nie importuje `winhttp.dll`** ⇒ przemianować `winhttp.dll` → `version.dll`.
4. **`target_assembly` wskazuje nieistniejący plik** ⇒ Doorstop kończy się cicho.
5. **Steam verify/aktualizacja podmieniła `winhttp.dll`** na oryginalny (oryginał ma ~100 kB i podpis MS;
   Doorstop z be.788 ma 26 112 B) albo usunęła `doorstop_config.ini`/`dotnet\`.
6. **Brak `dotnet\coreclr.dll`** / antywirus blokuje proxy.
7. Dopiero na końcu: za nowa metadata (107/108) albo brak base libs dla nowej wersji Unity.

## Linki

**GitHub / infra:**
- BepInEx: https://github.com/BepInEx/BepInEx
- Builds BE: https://builds.bepinex.dev/projects/bepinex_be
- Il2CppInterop: https://github.com/BepInEx/Il2CppInterop
- Cpp2IL: https://github.com/SamboyCoding/Cpp2IL (gałąź `development`; `LibCpp2IL/Metadata/Il2CppMetadata.cs`)
- Dokumentacja BepInEx — instalacja: https://docs.bepinex.dev/articles/user_guide/installation/index.html
- Dokumentacja BepInEx — troubleshooting (m.in. rename `winhttp.dll` → `version.dll`, `HideManagerGameObject`,
  zmiana entry pointu `[Preloader.Entrypoint]`): https://docs.bepinex.dev/articles/user_guide/troubleshooting.html
- Issues do wzorców błędów: https://github.com/BepInEx/BepInEx/issues/1395 (metadata 107, Unity 6000.5.8f1),
  https://github.com/BepInEx/BepInEx/issues/1274 (metadata 39, Unity 6000.3)
- Release'y stabilne (5.x = tylko Mono): https://github.com/BepInEx/BepInEx/releases

**CarX:**
- SteamDB: https://steamdb.info/app/1826420/
- Sklep: https://store.steampowered.com/app/1826420/CarX_Drift_Racing_Online_2/
- Nexus (CDRO2): https://www.nexusmods.com/carxdriftracingonline2/mods/1 — **pod moderacją od 12 maja 2026**, plik niedostępny
- KiNO (dokumentacja dotyczy **pierwszego** CarX, BepInEx 5.x / Mono):
  https://locomoco28.github.io/kino/getting_started/installation/ i https://locomoco28.github.io/kino/troubleshooting/

## Pliki w workspace (z poprzedniej rozmowy)

- **`bepinex-diag.ps1`** (319 linii, UTF‑8 z BOM) — pełna diagnostyka, sekcje:
  1 lokalizacja · **1b boot** (proxy DLL, bitowość `.exe` vs proxy przez nagłówek PE, importy EXE,
  `enabled`/`target_assembly`/`redirect_output_log`, istnienie pliku z `target_assembly`, `dotnet\coreclr.dll`,
  `.doorstop_version`, `output_log.txt`) · 2 `GameAssembly` · 3 `global-metadata.dat` (magic + wersja, ocena vs 23–106) ·
  4 wersja Unity + URL base libs · 5 instalacja BepInEx (`changelog.txt`, zakres z binarki `LibCpp2IL.dll`,
  `interop`/`unity-libs`/`plugins`, `[IL2CPP]` z cfg) · 6 ostatnie błędy z `LogOutput.log`. Tylko czyta, nic nie zmienia.
- **`bepinex-diag.bat`** — launcher: `chcp 65001`, sprawdza obecność `.ps1` obok, próbuje `pwsh`,
  fallback `powershell`, oba z `-ExecutionPolicy Bypass`, na końcu `pause`.
- **`bepinex-diag-basic.bat`** — czysty batch bez PowerShell (obecność/rozmiar proxy, doorstop cfg,
  `.doorstop_version`, `coreclr.dll`, `GameAssembly`, hex z `certutil`, liczba plików w `core`,
  ostrzeżenie o miksie Mono/IL2CPP, listing `interop`/`unity-libs`/`plugins`, grep logu).
- **`bepinex-po-aktualizacji-gry.md`** — przewodnik (sekcje 0 / 0.5 Szybka naprawa / 1 / 2 A,B0,B,B2,C / 3 / 3.5 / 4 / 5 / 6 / 7 / Źródła).

## Co już przetestowano

- `bepinex-diag.ps1` uruchomiony w **PowerShell 7.4.6** na dwóch sztucznych instalacjach z prawdziwym
  `winhttp.dll` z paczki be.788: parser 0 błędów; sekcja 1b dla pary x86/x64 wypisała ostrzeżenie o niezgodnej
  bitowości + `importuje winhttp.dll : NIE`, dla x64/x64 `Bitowosc EXE i proxy sie zgadza` + `TAK`;
  sekcja 5 poprawnie wyciągnęła „We support 23‑106" (be.788) i „We support 23‑108" (dev 1743).
- **Oba `.bat` NIE były uruchamiane** — w sandboxie nie ma `cmd.exe` ani Wine. Przeszły tylko przegląd
  statyczny (bilans nawiasów 0, wszystkie `goto` mają etykiety, brak gołych `>`/`|` w `echo`,
  `EnableDelayedExpansion` dla `!IN!`).

## Czego jeszcze nie wiem (do ustalenia w tej rozmowie)

1. Czy w `BepInEx\core\` jest miks Mono + IL2CPP (listing folderu).
2. Rozmiar/data `winhttp.dll` u użytkownika (czy to 26 112 B z Doorstop, czy oryginał Steam).
3. Bitowość `.exe` gry i którym `.exe` startuje Steam.
4. Który build BE jest wgrany (`be.788`? `win-x64`?) i czy nie jest zmieszany ze starym.
5. Zawartość `doorstop_config.ini` (zwłaszcza `target_assembly`).
6. Czy istnieje `BepInEx\LogOutput.log` i jaka ma datę.
7. Jaka wersja Unity i jaka wersja metadata po patchu 0.20.1 (na razie nieznane).

## Pierwszy krok

Zapytaj o **konsolowy output z `bepinex-diag.bat`** (albo `bepinex-diag-basic.bat`), a gdy go dostaniesz —
wskaż konkretną przyczynę i konkretną poprawkę. Nie proponuj „poczekaj na patch", dopóki nie wykluczysz
punktu 1‑6 z listy hipotez.
