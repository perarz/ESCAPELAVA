# Przegląd całego kodu gry — 25–26.10.2026

Zakres: całe `src/`, 85 istniejących plików Luau oraz nowy helper `ToolActivation` — łącznie 86 plików, około 30,8 tys. linii. Agent główny i trzech subagentów, rozłączne obszary edycji. Główne skrypty Command Bar sprawdzone osobno, bez wykonywania. Wygenerowane artefakty animacji, materiały marketingowe oraz modele i UI placu nie są kodem runtime objętym tym przeglądem.

W tej fali zmieniono **33 pliki w src: 32 istniejące i jeden nowy**, względem stanu po poprzednim częściowym przeglądzie, oraz **2 narzędzia korzenia** — łącznie 35 plików kodu. Zachowano wcześniejsze robocze zmiany Kacpra. Bez commita, pushu i publikacji.

## Kryteria

- Usuwać zbędną pracę i kopie logiki, zachowując istniejący wynik i kontrakt.
- Nie obniżać jakości FX, liczby efektów, częstotliwości sterowania, zasięgów, budżetów ani jakości fizyki dla oszczędności CPU.
- Nie zmieniać balansu, reguł rundy, wyglądu, spawnów ani zasad kar antycheata.
- Naprawy błędów mają odtwarzać istniejące zasady gry; wątpliwe zmiany zachowania zostają propozycjami.
- Odczyt Edit i parsowanie nie są testem gry. Brak zmierzonego wzrostu FPS lub czasu CPU.

## Wdrożone poprawki błędów i odporności

| Miejsce | Problem i wynik zmiany |
|---|---|
| `ItemService.give` | Przy pełnym stosie przycinał ilość, ale zwracał sukces, więc sklep mógł pobrać kasę bez dodania sztuki. Teraz pełny sukces albo `inventory_full`, także dla zakupu wielu sztuk; limit bez zmian. |
| `PlayerDataService` | Błąd load kończący się po wyjściu gracza mógł odtworzyć w Studio cache i wysłać `loaded_default` dla usuniętego gracza. Guard kończy tę ścieżkę przed fallbackiem. |
| `DebrisService.scan` | Kawałek zakolejkowany do pęknięcia pomijał liczniki, a potem `unregister` odejmował go ponownie. Oryginał jest liczony do czasu faktycznego podziału, także jeśli podział nie powstanie. |
| `DestructionService`, `BombService`, `CarService` | Zaległa praca po `task.wait`, oczekiwaniu na budżet i timerze zapłonu mogła przejść przez reset. Generacje rundy unieważniają stare operacje, a Bomb sprawdza generację również przed damage po powrocie z destrukcji. Stary wybuch nie ma ruszać nowej mapy ani nowej rundy. |
| `BridgeService` | `BuildBridge` sprawdzał ilość i pozycję, ale nie to, czy gracz wybrał most. Tryb budowania ma teraz właściciela na serwerze, a użycie wymaga tego trybu i mostu w loadoucie. Fallback bez kosmetycznego blueprinta pozostaje. |
| `BridgeService` | Chowanie blueprinta nie przepada przez cooldown equipowania. Koniec rundy kończy tryb i usuwa Tool ocalałych; zmiana postaci czyści autoryzację. |
| `GrappleService`, `BombService` | Użycie wymaga rzeczywiście trzymanego narzędzia i itemu w loadoucie. Sam zapas haka lub odwołanie do bomby przeniesionej do Backpack nie daje zgody na użycie. |
| `GrappleService`, `GrappleController` | Serwer planuje finalny łuk przed consume i sprawdza ten sam próg minimalnego czasu co klient. Liczba 0,01 s została przeniesiona z klienta do Config; zaakceptowane loty mają ten sam kształt i tempo. Różnica pozycji klient/serwer przy pingu nadal wymaga Play. |
| `MovementController` | Oczekiwanie na Humanoid istniejącej postaci opóźniało podpięcie HeadAim/BombHit/CharacterAdded. Listenery są podpinane bez tego oczekiwania; żeton chroni przed dokończeniem starej inicjalizacji. |
| `MovementController` | Nowa postać innego gracza nie dziedziczy poprzedniego skrętu głowy. Stan rozpoznaje konkretną postać i zachowuje pierwszy pakiet nowego rigu, gdy wyprzedzi odroczone CharacterAdded. |
| `TextShadowController`, `DebrisFXController` | Stabilne rejestry powiązań z jawnym sprzątaniem zastępują słabe wpisy Instance. Usunięcie samego cienia odpina też jego listenery na bazowej etykiecie; przejęcie tej samej dekoracji nie tworzy kolejnej kopii. |
| `UIController` | Licznik korzysta z istniejącego końca stanu w czasie serwera. Opóźnienie pakietu nie dodaje już czasu względem 3-2-1. Pozostaje fallback dla starego payloadu. |
| `CashCounterController` | Powtórny snapshot podczas lotu banknotów nie zeruje `pending`, po czym doloty odejmowały je drugi raz. Loty trwają dalej i rozliczają się do rzeczywistego salda. |
| `init.client` | Listenery gotowości czterech stanów są podpięte przed wymaganiem kontrolerów, żeby ich ładowanie nie opóźniało zapamiętania odebranych stanów. |

## Wdrożone optymalizacje i usunięte powtórzenia

| Miejsce | Usunięta praca / zachowany wynik |
|---|---|
| `ToolActivation` + pięć kontrolerów itemów | Jedna obserwacja postaci i wspólne podpinanie/odpinanie Activated zamiast pięciu kopii. Ponowne przeniesienie tego samego Toola nie pomnaża listenerów. C4 zachowuje osobne InputBegan i deduplikację dla PC/R2. |
| `Utils.attachHeldModel/makeHeldTool` | Bomb, Bridge i Grapple korzystają ze wspólnego montażu modelu, tak jak pozostałe itemy. Wybór Handle, spawy, masa, grip, światło bomby i awaryjna kula pozostają. |
| `BombService.destroyEnvironment` | Jedna obsługa destrukcji i jej błędów dla bomby oraz wybuchów RPG/C4/aut. Oddzielne reguły sprawcy i sprzątanie pocisku zachowane; destrukcja nadal poprzedza damage. |
| `Pieces.pickReuse` | Jedna reguła pozostawiania oryginału pod stopami dla v3/v4/rumowiska. Transformacje stóp liczone raz na cięcie zamiast per resztka. Tolerancje, scoring i remisy bez zmian. |
| `StructureCore.collectParts` | Geometria i nazwa do sortowania liczone raz per part zamiast per porównanie. Kolejność kluczy, zaokrąglenia, SID i hash pozostają. |
| `CashPickupService` | Pusty folder nie skanuje graczy. W nieyieldowanym ticku pozycja gracza odczytana raz, zamiast dla każdej paczki. Częstotliwość, zasięg i wybór najbliższego bez zmian. |
| `DebrisService.makeRoom` | Jedna lista pozycji żywych graczy na przebieg zamiast odczytów postaci dla każdej platformy. Ochrona platform blisko gracza pozostaje. |
| `CollapseService.enqueue` | Jedna lista pozycji wszystkich postaci na plan zamiast per grupa. Celowo nie zmieniono tego na filtr tylko żywych; priorytety zachowane. |
| `DebrisService`, `BridgeController` | Ponowne użycie parametrów promieni zamiast tworzenia nowych przy każdym zapytaniu. Filtry nadal aktualizowane, bez cache pozycji przechodzącego do kolejnej klatki. |
| `RpgController`, `C4Controller` | Rekordy nakładki na stawy powstają raz na gest, zamiast trzech tabel w każdej klatce aktywnej animacji. Ta sama krzywa, czas i kolejność faz Animatora. |
| `EnergyDrinkController` | Stałe CFrame gestu łyku policzone raz, zamiast konwersji kątów per staw per klatka. |
| `InventoryController.layoutBackdrop` | Te same cztery prostokąty tła, bez pięciu tymczasowych tabel w każdej klatce. |
| `DebrisFXController.cloneLooseParts` | Wspólne przygotowanie kopii dla przewracania i rozsypania: te same części, skrypty i spoiny; bez zmiany losowań i liczby efektów. |
| `RagdollState`, `UIController` | Bez zbędnego wyszukiwania Playera po lokalnej postaci; bez zapisu identycznego tekstu timera co klatkę. |
| `Utils.isFiniteVector3` | Wspólne sprawdzenie poprawności wektora dla Bridge/Grapple/RPG/C4; zachowane dodatkowe limity pozycji mostu. |
| `CashService` | Diagnostyka transakcji ma rzeczywisty `unix_ms` i dotychczasowy powód, zamiast czasu od startu serwera. |

Poprzednie optymalizacje ItemEquip i filtrów lotu C4 oraz blokada SetLoadout poza lobby pozostają; szczegóły w [pierwszym przeglądzie](ITEM_REVIEW_2026-10-25.md). Nie liczyć ich ponownie jako nowych zmian tej fali.

## Pokrycie i weryfikacja

| Obszar | Pokrycie |
|---|---|
| Serwisy serwera | 32/32: dane, runda, gracze, waluty, sklep, nagrody, wszystkie itemy, lawa, ragdoll, upadki, anty-cheat, destrukcja. |
| Structure | 6/6: Core, Bake, BuildingState, CollapsePlanner, Pieces, StructureTests. |
| Kontrolery i helpery klienta | 34/34, wliczając nowy ToolActivation. |
| Shared | 11/11: Config, Remotes, Utils, definicje, Destructible, Fracture, Shockwave, GrappleArc, Ladders, Dev. |
| Bootstrap i ładowanie | Oba init oraz ReplicatedFirst.LoadingScreen. |
| Narzędzia korzenia | 9/9, 787 linii przed zmianami: STRUCTURE_BAKE, STRUCTURE_TEST, LIGHTING_REVERT, INTERIOR_LAMPS, LAMPS_LIGHTS, TRAFFIC_LIGHTS, WINDOWS_GLASS, LADDERS_TAG, INTERIOR_LAMPS_OUTSIDE. |

W narzędziach poprawiono dwa problemy, **bez ich wykonywania**: `WINDOWS_GLASS.revert` cofa tylko szyby o tym samym podpisie co apply, nie wszystkie materiały Glass w mapie; `STRUCTURE_TEST` wymaga świeżych klonów całego folderu Modules, aby nie brać starego ItemDefinitions z cache. Jednorazowe skany geometrii w INTERIOR_LAMPS pozostawiono — nie wpływają na FPS gry.

- Budowa Rojo i `git diff --check` przeszły.
- Wszystkie 86 plików przeszło `pcall(loadstring, Source)` w Studio Edit. Funkcji z tych źródeł nie uruchamiano; to kontrola składni, bez pełnej analizy typów.
- Osobno sprawdzono składnię źródeł wszystkich 9 narzędzi korzenia, również bez wywoływania otrzymanych funkcji. Łącznie kontrola składni: 95/95 plików Luau.
- Długości w bajtach i sumy źródeł porównano z dyskiem (`h = (h*31+bajt) % 2147483647`). Studio: ESCAPE LAVA, placeId 107369017875577.
- Przejrzano połączone zmiany, zachowanie wywołań helperów i brak nowych cykli require.
- Bez Play, pomiaru FPS, testu fizyki i publikacji. Konkretne sprawdzenia: [TESTY](TESTY.md), sekcja pełnego przeglądu z 26.10.

## Pozostawione ustalenia i większe usprawnienia

1. **Bootstrap nadal może zatrzymać grę po błędzie require/init.** Samo owinięcie wszystkiego w pcall i kontynuowanie mogłoby uruchomić rundę bez zapisu danych, walidacji lub destrukcji. Wymaga podziału zależności na krytyczne i opcjonalne oraz jawnego zachowania po awarii. Nie wprowadzono częściowo działającego serwera.
2. **Spawny do rundy pozostają sekwencyjne.** Może to być większy koszt przy wielu graczach. Zmiana wymaga osobnego projektu gotowości postaci i zgody na ingerencję w spawnowanie.
3. **HeadAim nadal rozsyłany do wszystkich odbiorców.** Filtrowanie po widoczności/dystansie może dać większy zysk sieciowy, ale wymaga granicy jakości i wysłania aktualnej pozy po wejściu w zasięg. Nie zgadywano promienia.
4. **Anty-cheat ma dotychczasowe ograniczenia poziomu/pionu.** Nie dokładano kar ani reguł, które mogłyby karać legalny hak, ragdoll, odrzut lub pływanie w lawie. Obowiązuje istniejący plan paczki 6.
5. **Zapisany bake nie sprawdza MapRevision, a hash nie obejmuje permanent.** Zmiana Locked/StructPermanent bez geometrii może zostawić nieaktualny bake. Do domknięcia przed użyciem zapisanych danych, razem z porównaniem serializacji do 0,001. Obecny STATUS nie potwierdza aktywnego bake'u.
6. **Rebuild analizuje budynki bez bake'u na początku lobby.** Cache mógłby ograniczyć ten koszt, ale musi poprawnie wiązać nowe instancje, gości i konfigurację. Nie dodawano cache'u mogącego używać starej mapy.
7. **Stałe rumowisko pod lawą nie przechodzi tej samej ścieżki kasowania co tymczasowe.** Możliwa oszczędność fizyki; wymaga oceny podparcia innych obiektów. Nie usuwano platform na podstawie nowej reguły.
8. **Drag ekwipunku nie identyfikuje jednego palca.** Drugi dotyk może poruszyć lub zakończyć pierwszy drag. Do poprawy z całą obsługą telefonu i ustalonymi gestami.
9. **KillMessage i WinMessage mają podobną obsługę tweenów/fade.** Kandydat na helper z zachowaniem pierwszeństwa wygranej; sam duplikat nie uzasadnia ryzyka zmiany komunikatów w tej fali.
10. **Subskrypcje PlayerData uruchamiają również odbiorców ignorujących `updated`.** Filtrowanie po typie zdarzenia może ograniczyć liczbę zadań; wymaga wspólnej zmiany kontraktu wszystkich konsumentów.
11. **BuildBridge ogranicza tempo sukcesów, a odrzucone żądania nadal wykonują walidację i odpowiedź.** Osobny limit zalewu żądań warto zaprojektować tak, aby nie blokował poprawki po zwykłym odrzuceniu budowy.
12. **Streaming pozostaje wyłączony.** Ponowne włączenie wymaga sprawdzenia cache stawów i referencji w handoff. Obecny przegląd nie potwierdza gotowości streamingu.

Są to ustalenia lub kierunki dalszych prac, nie obietnica, że wszystkie są nowymi błędami ani że gra została przetestowana pod docelowym obciążeniem.
