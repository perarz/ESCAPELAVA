# Częściowy przegląd itemów — 25.10.2026

Zakres: obsługa wyposażania/używania Bomby, C4 i RPG, gest wyciągania oraz bezpośrednie zależności inventory/loadoutu. Praca: agent główny i jeden subagent, bez dalszego delegowania. Pozostałe itemy i całe systemy destrukcji/ruchu nie zostały objęte pełnym przeglądem.

## Wdrożone

| Miejsce | Ustalenie i zmiana | Korzyść |
|---|---|---|
| `ItemEquipController` | Kąty zamrożonego Config przeliczane do CFrame raz; brak interpolacji gestu przy zerowej wadze. Pozostaje dotychczasowy blend chwytu i obsługa przerwań. | Usunięcie powtarzanych konwersji dla stawów każdej obserwowanej postaci co klatkę. |
| `C4Service.step/update/fly` | Jeden filtr promieni na klatkę z lecącymi ładunkami, przekazywany do wszystkich lotów. Same przyklejone ładunki nie budują filtra. Rzut przy dłoni zachowuje osobny filtr. | Z N budów filtra na klatkę do jednej: odpada N−1 pobrań graczy, list postaci i obiektów RaycastParams. Pętla nie yielduje; kolejna klatka odświeża filtr. |
| `LoadoutService.onSetLoadout` | Brakowało kontroli LOBBY, mimo deklaracji w kontrakcie. Odrzucone żądanie odsyła aktualny stan. | Zablokowanie podmiany trzech wybranych itemów bezpośrednim żądaniem podczas rundy. |
| `BombService.onEquipItem` | Chowanie bomby po wyborze innego itemu poprzedza jej cooldown equipowania, tak jak w RPG/C4. | Własny cooldown bomby nie zostawia jej w postaci, gdy drugi serwis przyjmie przełączenie. |
| `RpgService.handleFire`, `C4Service.handleThrow` | Odrzucenie wektorów o nieskończonej długości obok dotychczasowej kontroli NaN, przed consume. | Nieprawidłowa normalizacja nie zużywa itemu ani nie tworzy uszkodzonego lotu. |

Nie zmieniano balansu, sterowania, modeli, UI ani kontraktów remote'ów. Nie mierzono wzrostu FPS ani czasu CPU; powyższe korzyści wynikają z usuniętych operacji, nie z pomiaru rozgrywki.

## Weryfikacja

- Budowa projektu Rojo zakończona poprawnie.
- `git diff --check` bez błędów.
- Studio `ESCAPE LAVA`, placeId 107369017875577, tryb Edit: źródła pięciu plików zgodne z dyskiem według długości w bajtach i sumy `h = (h*31+bajt) % 2147483647`.
- `pcall(loadstring, Source)` zwróciło poprawną funkcję dla każdego z pięciu plików; funkcji nie wykonywano. To kontrola składni, nie pełna analiza typów.
- Nie uruchamiano Play. Przypadki do sprawdzenia przez Kacpra: [TESTY](TESTY.md), sekcja przeglądu itemów z 25.10.

## Propozycje na osobny etap

1. `BombService.buildToolVisual` powiela składanie Toola z `Utils.makeHeldTool`, używanego już przez RPG/C4. Warto usunąć kopię po porównaniu gripa, Handle, światła i awaryjnej kuli. Zysk utrzymaniowy, bez obietnicy wzrostu FPS.
2. `BombService.detonate` i `explodeAt` powtarzają wywołanie destrukcji i obsługę jej błędów. Można ujednolicić ten fragment, zachowując różnice w sprzątaniu pocisku, logach i obsłudze sprawcy, który opuścił serwer. Nie zastępować jednej funkcji drugą bez porównania tych różnic.
3. Kop RPG i zamach C4 mają podobne nakładki na stawy, z tymczasowymi tabelami tworzonymi podczas animacji. Ewentualny wspólny helper powinien zachować kolejność PreAnimation/PreSimulation i odrębne zasady przerwań. Krótkie gesty mają niższy priorytet niż ciągły chwyt RPG.

To propozycje, nie zaimplementowane poprawki ani potwierdzone regresje.
