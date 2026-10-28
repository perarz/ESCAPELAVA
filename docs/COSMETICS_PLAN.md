# COSMETICS — sklep i garderoba

> **Punkt wznowienia 27.10:** aktualny stan i ostatnie decyzje są w [STATUS — COSMETICS](STATUS.md#cosmetics--punkt-wznowienia-27102026). Poniżej zachowano historię planu; starsze opisy brakujących importów, studsów, zakładek i BACK/X nie są aktualnym zleceniem. Import wszystkich trzech modeli zakończony. Najbliższy krok to wskazane w STATUS testy Kacpra, nie ponowny import ani budowa od początku.


Ustalenia z Kacprem, 26.10.2026. **Implementacja rozpoczęta na polecenie „chyba możemy zacząć”.** Kacper zezwolił na jednego nadzorowanego subagenta i osobno zatwierdził budowę UI przez agenta („Tak, zbuduj też UI”). Kod klienta/serwera i UI przygotowane; import modeli wymaga dokończenia — bieżący stan w STATUS. Nie traktować propozycji wizualnych poniżej jako potwierdzonej oceny gotowego UI.

## Zatwierdzone

**27.10 — uproszczenie COSMETICS na prośbę Kacpra:** usunięto Wallet, napis ESCAPE LAVA / THE CLOSET, zakładki i etykiety kategorii. Wszystkie produkty we wspólnym katalogu (garderoba nadal tylko posiadane). Sam licznik kasy po lewej, poniżej kontrolek Robloxa; główny tytuł wyśrodkowany. Kategorie wyposażenia i zapis pozostają bez zmian. Kopia UI: `ServerStorage.CosmeticsUI_v2_2710`; skrypt zmiany: `artifacts/cosmetics/simplify_ui.luau`. Build i kontrola Edit, bez testu Play. Wymagany Cmd+S.

- Stoisko w lobby / istniejąca `Workspace.ClothesShopScene`, napis **COSMETICS**, otwiera sklep.
- Osobny przycisk **COSMETICS pod INVENTORY** otwiera garderobę z posiadanymi kosmetykami. Dostęp tylko w lobby.
- UI: ciemne tło, intensywne kolory, pionowe przewijanie, kafelki różnych rozmiarów. Ma pasować do istniejącego UI, ale ograniczać dominację żółtego i Studs. Łączyć gładkie powierzchnie z akcentami Studs.
- **Korekta Kacpra 26.10 po pierwszej wersji: sklep ma zajmować CAŁY EKRAN**, z bardziej nietuzinkową kompozycją; poprzednie małe okno było zbyt proste. X ma być spójny z Inventory. Wdrożono drugą wersję: pełne ciemne tło, duży nagłówek, bezpośrednie zakładki kategorii, asymetryczna wystawa, duże napisy kategorii w tle i obwódki za podglądami, stałe stopki z ceną. X sklonowany z `Inventory.Panel.Body.CloseButton`, nie rysowany na nowo.
- Kafelki prezentują akcesoria na manekinie lub odpowiednio wykadrowanej części postaci; cena w rogu. Dokładna kompozycja pozostaje do oceny.
- Kliknięcie produktu przełącza widok na istniejącą przebieralnię. Podgląd to **lokalna kopia postaci gracza**, nie teleport prawdziwej postaci; użytkownicy nie zasłaniają sobie podglądu.
- Przymierzanie nie zmienia zapisanego stroju. ~~Zakup przez **BUY**, potem osobne **EQUIP**~~ — **27.10: BUY od razu zakłada** (decyzja Kacpra); garderoba umożliwia **EQUIP / UNEQUIP**.
- **27.10 wieczór, sklep v4:** układ bez zmian, wygląd jak sklep w dużych grach (Fortnite) w języku ESCAPE LAVA. Kolor karty = **rzadkość** (COMMON/RARE/EPIC/LEGENDARY + sezonowe HALLOWEEN), nie kategoria. Przypisanie: dynia HALLOWEEN, kamizelka EPIC, plecak RARE.
- Kupowanie za istniejącą gotówkę z gry, zakup na stałe.
- Ceny zaakceptowane 26.10: **HalloweenPumpkin 500, KevlarVest 750, SchoolBackpack 600**. Jedno źródło w kodzie: `Config.Cosmetics.Prices`.
- Kategorie, po jednym dodatku na kategorię, możliwe łączenie różnych kategorii. Przykłady uzgodnione: głowa/czapka, tors/kamizelka, twarz; plecy wynikają z dostępnego plecaka. Ostateczna lista zależy od oferty.
- Zapisywać zarówno posiadane kosmetyki, jak i założony zestaw; odtwarzać po ponownym wejściu i respawnie.
- Na start obecne modele jako placeholdery, później kolejne modele w Blenderze. Kosmetyki bez bonusów do gameplayu; kamizelka nie oznacza zatwierdzenia pancerza.

## Sprawdzone zasoby

Odczyt folderu `assets/models` i Studio Edit 26.10.2026:

| Kosmetyk | Kategoria | Pliki |
|---|---|---|
| HalloweenPumpkin — dyniowy kaptur | Głowa | `assets/models/HalloweenPumpkin/` oraz wersje w korzeniu `assets/models`, Blender i FBX |
| KevlarVest — kamizelka kuloodporna | Tors | `assets/models/KevlarVest.blend`, `KevlarVest.fbx` |
| SchoolBackpack — plecak szkolny | Plecy | `assets/models/SchoolBackpack/`, Blender, FBX i podglądy |

To **3 różne produkty**, nie liczyć kopii, backupów i wariantów roboczych jako kolejnych kosmetyków. W folderze nie znaleziono osobnego modelu na twarz. Czapka z daszkiem, bandana, kask i nauszniki w `AKCESORIA_PROMPTY.md` to briefy, nie potwierdzone gotowe assety. Import i przygotowanie tych trzech produktów jako akcesoriów w grze pozostają do weryfikacji; plik FBX nie oznacza gotowości w Studio.

Platforma znaleziona w Edit: **`Workspace.ClothesShopScene.Decoriations.Platform.platform`** (pisownia `Decoriations` jest rzeczywista). Nie zmieniano sceny. W scenie są też foldery manekinów, ubrań dekoracyjnych i wieszaków; dekoracje nie są automatycznie ofertą sklepu.

## Propozycje do dopracowania — jeszcze nie zatwierdzone

- Konkretna paleta, proporcje kafelków, ich rozmieszczenie, oznaczenia OWNED/EQUIPPED i ostateczny wygląd obu paneli.
- Efekty: subtelne powiększenie podglądu, lekki obrót, pojedynczy połysk po wyborze; odpowiednik na dotyku. Animować przede wszystkim oglądany produkt, nie cały katalog stale.
- Obracanie podglądu w przebieralni; przycisk BACK i powrót do zachowanej pozycji katalogu.
- Fizyczna szafka może być dekoracją lub dodatkowym wejściem; nie jest wymagana po uzgodnieniu przycisku COSMETICS.
- Warianty kolorystyczne, kolejność i wyróżnienia oferty, ocena konkretnych kadrów i wyglądu.

Inspiracje obejrzane podczas rozmowy (inspiracje wizualne, nie gotowe rozwiązania Roblox): [Aceternity Bento Grid](https://ui.aceternity.com/bento-grid), [SUI Bento Grid](https://structui.com/components/bento-grid).

## Następny krok

Przygotować modele w Studio według [kontraktu](STUDIO_CONTRACT.md). Próba dostępu do okna Studio przez narzędzie obsługi pulpitu zakończyła się timeoutem; nie zaimportowano FBX. UI zbudowano po osobnej zgodzie i obejrzano w Edit: ciemny panel, trzy kolorowe kafelki (dynia większa), przycisk pod Inventory, ustawienia przesunięte niżej. To kontrola układu, nie akceptacja Play. Nie uruchamiać Play; testy gry przeprowadza Kacper. Nie zmieniać wyglądu otoczenia przy okazji.

## Realizacja w kodzie

- `CosmeticDefinitions`: stabilne ID, nazwy, kategorie i punkty zaczepienia. `CosmeticsService` jest właścicielem posiadania i wyposażenia; `CashService.purchase` zatwierdza pieniądze i własność razem w jednym nieyieldowanym zastąpieniu stanu.
- `PlayerDataService`: nowe pole `cosmetics = { owned, equipped }` w tym samym zapisie, bez zmiany namespace i bez kasowania wcześniejszych pól. Blokada transakcji podczas końcowego zapisu/wyjścia.
- Przywrócenie stroju przez callback po bazowym wyglądzie w `AppearanceService`; bez zmiany sposobu spawnu. Walidacja lobby, odległości od właściwego NPC przy zakupie, ceny, własności, modelu i attachmentów.
- `CosmeticsState`: kopia stanu serwera po stronie klienta, listener przed ClientReady. `CosmeticsController`: katalog, filtrowanie, garderoba, przymierzanie i obrót, BUY/EQUIP/UNEQUIP, blokada podwójnego kliknięcia i informacja przy braku odpowiedzi.
- `CosmeticsPreview`: lokalny model z usuniętymi skryptami, narzędziami, FX i fizyką; brak kolizji, dotyku i zapytań. Podgląd i rzeczywiste akcesoria używają tego samego montażu attachmentów.
- Start rundy / usunięcie postaci / zamknięcie usuwa podgląd i przywraca kamerę, Ambient i sterowanie. Otwarte kosmetyki wykluczają Inventory, sklep broni i ustawienia, bez zmiany ich wyglądu.
- Dodawanie produktu: przygotować Accessory w folderze placu, dopisać definicję i cenę. Nowa kategoria wymaga wpisu w categories i koloru UI; katalog nie ma osobnych handlerów dla każdego ID.

Weryfikacja 26.10: 93 pliki server/client/shared porównane bajtowo/sumą z Edit, wszystkie parsują się; `rojo build` i `git diff --check` bez błędów. Jednego subagenta użyto do serwera i przeglądu klienta; poprawiono obsługę nieudanego montażu oraz pozę podglądu. Nie testowano Play, zapisu DataStore na żywo ani zachowania FBX (brak importu). Lista do sprawdzenia w TESTY.

Druga wersja UI: kontrola zrzutem w Edit, składnia i zgodność trzech zmienionych modułów (`CosmeticsController`, `CosmeticsPreview`, `Config`) oraz build/diff-check. Kopia pierwszego UI: `ServerStorage.CosmeticsUI_v1_2610`. `artifacts/cosmetics/fullscreen_ui.luau` zapisuje budowę drugiej wersji. Brak importu nadal blokuje sprzedaż; zamiast pustych kart widać neutralne manekiny z PREVIEW SOON / COMING SOON (nie zastępują produktów). Tymczasowe karty do oceny Edit usunięte po zrzucie. Play użytkownika nie był zatrzymywany — zmiany placu po jego powrocie do Edit.

**27.10 — import dyni zakończony:** `ReplicatedStorage.Cosmetics.HalloweenPumpkin` zawiera 4 MeshParty i HatAttachment (0,0.445,0) względem Handle, 3 weldy, prawidłowe kolory, brak kolizji/masy i SmoothPlastic. Rozmiar ok. 1.90 × 1.91 × 1.92 studa. Mocowanie obejrzane na nieruchomej kopii StarterCharacter w Edit; kopia podglądu usunięta. Oryginał importu zachowany w `ServerStorage.HalloweenPumpkin_Imported_2710`. Cena 500, katalog i zakup korzystają z istniejącej definicji. Kamizelka i plecak czekają na import użytkownika; Play i zapis Cmd+S niepotwierdzone.


27.10: All three accessory imports complete. Current status in STATUS; attachment details in STUDIO_CONTRACT.

27.10 fitting revision: full-screen scene, hidden catalog header and HUD while cosmetics is open (HUD restored on close), bottom purchase strip, BACK/X. TurnLeft/TurnRight removed; Fitting.RotateArea handles mouse/touch drag, global release and window focus cleanup. Camera framed from character bounds. Removed native rectangular GUI borders and card Orbit. Backup: ServerStorage.CosmeticsBeforeFitting_2710. Edit screenshot checked, source parse/sync and Rojo build passed; Play interaction not tested.
