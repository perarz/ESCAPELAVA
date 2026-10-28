# Audyt kontekstu — 23.10.2026

Sprawdzono dokumenty w `docs/`, lokalną historię i zmiany Git, istotne źródła usług/kontrolerów/Config/Remotes oraz wybrane obiekty otwartego placu **ESCAPE LAVA, 107369017875577**, w **Edit**. To audyt spójności kontekstu, nie ponowny pełny code review ani test gry. Nie uruchamiano/zatrzymywano Play i nie zmieniano placu.

## Organizacja dokumentacji

Bieżący status jest odtąd w **STATUS.md**; README pokazuje właścicieli tematów. Wspólne zasady agentów w CLAUDE.md, docs/AGENTS.md kieruje do nich bez drugiej kopii. PROJECT_CONTEXT opisuje produkt, ROADMAP decyzje/dalszy kierunek, DO_RELEASE zadania, TESTY akceptację. ARCHITECTURE i STUDIO_CONTRACT opisują aktualny kod/nazwy; DESTRUCTION_PLAN i REVIEW mają wyraźne rozróżnienie aktualnych reguł/indeksu oraz historycznych raportów.

Wersje dokumentów sprzed audytu zachowano w **archive/2026-10-23**. Zawierają przyczyny zmian i dawne pomiary; nie stanowią dzisiejszych instrukcji. Nie przenoszono do bieżącego backlogu wycofanych eksperymentów.

## Rozbieżności poprawione

| Dawny zapis / sprzeczność | Stan po sprawdzeniu / korekta |
|---|---|
| STATUS agentów z 28.09, wiele kopii kolejki | Jeden STATUS z datą i granicami weryfikacji; stare wpisy w archiwum. |
| Loadout „do wdrożenia”, wybór miejsca UI otwarty | Wdrożony 18.10, Inventory, trzy sloty, tylko lobby. |
| Slot3 nie istnieje / nowy item wymaga SlotN | Slot1–3 obecne w Edit; slot = wybór loadoutu, nowy typ itemu nie dokłada slotu. |
| Klik karty wkłada/wyjmuje, hover zmienia DETAILS, klik tła zamyka | Klik otwiera DETAILS; ADD/REMOVE/SWAP wybiera; klik tła nie zamyka. Poprawione oczekiwania testów. |
| DETAILS to ViewportFrame | Lokalny model w świecie przed kamerą; Window jest Frame. Kod i odczyt Edit. |
| Bomba „bez wybuchu”, most „brak czym niszczyć” | Destrukcja działa w kodzie; brak pełnej akceptacji jest osobnym statusem. |
| Brak RPG/napoju lub RPG etap 2 = rocket jump | RPG/napój w kodzie i commicie; efekty/odrzut RPG już są. Rocket jump wycofany 21.10. Sticky bomb nadal brak kodu. |
| Napój bez bonusu prędkości / kolorowy efekt bez doprecyzowania | 10 s staminy bez końca, chód +3, sprint bez zmian, FOV +5, złota oprawa. |
| Lobby 15/30 s, Spawn 5 s, fazy lawy | Lobby 25; osobne PREPARING i COUNTDOWN 3; jedna runda bez faz, FINISHING 3, RESETTING, POST_ROUND 10. |
| Wypłaty z RoundEnded / po Endgame | RewardsService słucha RoundFinished przed cleanupem; RoundEnded jest cleanupem bez payloadu. |
| Stare produkcyjne fazy 0,6/1,2/2/3 | Runda 80 s, płynnie 0→3; testowo 240 s, 0→1. Zmieniać czas i prędkość razem. |
| Wyliczenia końcówki oparte na dawnej wysokości i fazach | Zaznaczone jako historia; nowa krzywa wymaga nowego testu z graczami. Bez dopisywania nowej decyzji balansu. |
| Tylko OrangeBuilding na v4 / dalsza migracja przed nami | Wszystkie 10 nazw w Config już na v4; otwarte są testy, nie migracja. |
| Gruz przygniata / pół obrażeń za jazdę | Crush damage usunięty 29.09; zwykły fall damage pozostaje. |
| Dwa tryby grafiki, panel Potato/Full i G | Jeden Graphics.Profile; SettingsService/QualityController/SetGraphicsMode usunięte. Ogólny panel SETTINGS nie jest gotowym systemem. |
| Fall damage — 5 zaległych prób niezaliczonych | Zaznaczone jako zaliczone przez Kacpra 01.10 w TESTY; nie otwierać ponownie bez regresji. |
| Cały custom chód/idle/skok czeka na publikację | Wycofany 11.10; dawne checklisty zarchiwizowane. Został osobny gest F. |
| Gest F bez pozycji na liście publikacji | AnimationId=0 / StudioPreview=true; potrzebne ID dla gestu na live. Sama mechanika F jest osobna. |
| Most ma długość 13,25 | Odczyt bbox Edit ~5,72×0,60×16,25; współdzielone worldSize z modelu. |
| Marker kamery haka wymagany | Markery wyłączone, kadry automatyczne yaw 20° / pitch 12°. |
| Ruchomy ShopLight jako aktualny kontrakt | Nowsza robocza zmiana 23.10: stałe ShopLights; stary LightName usunięty. Dopisany test CameraSubject po respawnie przy otwartym sklepie. |
| Lawa wymaga Texture / aktywny Crust_v2 lub Liquid_v6 / siatka 16×16 | Edit: Basalt + EscapeLava_RoundedRed_v4; Texture opcjonalne, siatka 24×24, amplituda 1,05, ambient FX v5. |
| MinSurfaceY wyłącza całą oprawę wraz z falami | Próg/histereza dotyczy ambientu, nie siatki fal w kanale. |
| Dawne „finalne” Lighting z 16/29.09 | Bieżące wartości i Realistic z default.project.json, bez wymuszania starego ShadowMap/Atmosphere/Bloom. |
| Stary StructureService nadal opisany jako aktywny | Usunięty; StructuralService/CollapseService są właścicielami v4. |
| Stara lista remote’ów / AliveChanged bez odbiorcy | 36 nazw w źródle; ClientReady/Loadout/DrinkEnergy/Rocket* aktywne, AliveChanged obsługuje przejście rundy. |
| Paczki 1/2/4/5 oraz itemy 20–21.10 „niezacommitowane” | Lokalne commity 433b03a i 0d6c63c istnieją; paczka 3 eae677a, loadout 786fc03. Nie dowodzi to push ani Play. |
| Paczka 6 nadal czeka na dwie decyzje | Decyzje 30.09 zapisane; implementacja rollback/kill/kick/pionu jeszcze nie istnieje. |
| Anti-cheat już „wykrywa teleport” | Poziom co 2 s/3 strikes nie pokrywa pojedynczego skoku i lotu w pionie; brak cofania. |
| Odbudowa całego miasta co rundę | Od 07.10 tylko naruszone jednostki, nadal potrzeba pomiaru kosztu. |
| „Gotowość na 30–50” bez sprawdzenia spawnów | SpawnPoints pusty w Edit, fallback; ładowanie postaci sekwencyjne. MaxPlayers=20 w Config nie ustawia limitu miejsca. |
| Zapis bake’u jako dawne abstrakcyjne TODO | Brak modułów StructureData w Edit; runtime waliduje hash/wersję, nie MapRevision, zapis zaokrągla do 0,001. |
| Liczby modułów 28/29 i 21/23 | Na dysku 31 services, 32 controllers/helpery, 11 shared, 6 Structure. |
| Wcześniejsze eksperymenty/pancerze/eventy jako zadania release’u | Rozdzielono zatwierdzoną grę od dalszych kierunków. Nie dodano nowych bonusów/monetyzacji ani decyzji designowych. |

## Zachowane granice i nierozstrzygnięte sprawy

Wszystkie **31 istniejących wpisów `[x]` w TESTY zachowane**; audyt nie dopisał zaliczeń Play. Usunięto tylko jawnie zastąpione, niezaznaczone oczekiwania (np. wycofany chód, iskry z ikony i ciągły połysk kasy). Nie ma podstaw, by ogłosić T1–T7 zaliczone dwa razy, gotowość telefonu, skuteczność przyszłego anti-cheata lub FPS większego serwera.

Nie sprawdzano stanu zdalnego GitHub, zapisu placu na dysku ani opublikowanej wersji. Pierwsze sumy dwóch źródeł Studio zgadzały się z dyskiem, ale w trakcie audytu w innej sesji zmieniały się sklep/Config/plac i fragmenty dokumentacji — zachowano nowszą treść; wcześniejszy hash nie dowodzi synchronizacji kolejnej wersji.

Zmiany w źródłach tego audytu to **wyłącznie komentarze** w Config, Remotes, RewardsService, HeadTrackingService i UIController: aktualna rola Structure, nagrody/cleanup, handshake loadoutu, C0 i GET READY. Treść wykonywalną przed/po porównano bez komentarzy. Istniejących zmian mechaniki sklepu/Config nie cofano. Nie robiono nowego refaktoru ani nie uruchamiano Play.

## Sprawdzenia dokumentacji

Wykonano: kontrola lokalnych odnośników Markdown (0 brakujących celów), zgodność indeksu ze źródłem (31 services / 32 client / 11 shared / 6 Structure / 36 remote’ów), dokładne zachowanie wszystkich 31 wpisów `[x]` oraz `git diff --check` (bez błędów). Porównanie wykonywalnej treści pięciu źródeł przed/po potwierdziło, że zmiany audytu obejmują tylko komentarze. Pełny nowy przegląd bezpieczeństwa i obciążenia to osobna praca; ten raport porządkuje znane fakty i ich status.
