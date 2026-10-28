# Roadmapa i decyzje produktu

Aktualizacja: **23.10.2026**. Bieżący stan jest w [STATUS](STATUS.md), kolejka wydania w [DO_RELEASE](DO_RELEASE.md), testy w [TESTY](TESTY.md). „W kodzie” nie oznacza „potwierdzone w Play”.

## Zakres i decyzje obowiązujące

- Szybkie rundy: projektowo 80 s, lobby 25 s; lawa płynnie przyspiesza, bez dawnych faz. Produkcyjne liczby wdrożyć razem i ocenić z ludźmi.
- **Loadout: 3 itemy** z docelowych 6. Panel Inventory tylko w lobby, brak trzeciego stoiska. Sloty nie przesuwają się po zużyciu ostatniej sztuki.
- Wybrana szóstka: bomba, most, hak, RPG, energy drink, sticky bomb. **25.10: sticky bomb = C4** (decyzje Kacpra: rzucasz — dalej i płaściej niż bomba — i przykleja się do mapy, nie do graczy; maks. 3 naraz; odpalasz wszystkie klawiszem G / przyciskiem na telefonie; śmierć = ładunki znikają bez wybuchu). Cała szóstka w kodzie, C4 czeka na test. Nie zastępować wybranego zestawu dawną rekomendacją lotni/ściany/rozbiórki.
- **Fizyka destrukcji zostaje**. Całe miasto na v4, lokalny gruz bez kolizji, gruz nie rani, jazda na bryle podlega zwykłemu fall damage. Jeden profil grafiki; brak ustawień Potato/Full.
- **Wybuchy ranią wszystkich, także odpalającego**. Rocket jump usunięty 21.10. Odrzut RPG nie może zmieniać kierunku celowania kamerą.
- **Telefon:** przyciski dotykowe sprint/push/most. UI Kacper, logika agent. To zatwierdzony kierunek, nie otwarte pytanie „czy telefon w v1.0”.
- **Anty-cheat:** cofnięcie na ostatnią dobrą pozycję → powtarzane naruszenia: zabicie → kick; pion po około 1 s. Decyzje 30.09 zamknięte, implementacja paczki 6 pozostaje do zrobienia.
- **R15 z Motor6D**, oryginalny Animate. Własny kierunkowy chód/idle/skok wycofany 11.10. Został osobny gest F i kosmetyczne gesty itemów. Nie wracać do HumanoidDescription ani programowego wyrównywania skal postaci.
- Wygląd startowy losowany/zapisywany przez AppearanceService. Kolejne kosmetyki nie dają bonusów. Ragdoll i head tracking zostały naprawione odrębnymi zmianami; nie przypisywać naprawy head trackingu samej konwersji rigu.
- Komunikaty dla siebie: kill dla zabójcy, przetrwanie dla ocalałego. Opisy i UI po angielsku. Styl i wyjątek fontu loadingu: UI_RULES.

## PLAN: LOADOUT — wdrożony 18–19.10, czeka na pełną akceptację

Stan: `LoadoutService` jest właścicielem `data.loadout` (dokładnie trzy napisy, `""` = pusty slot); `LoadoutState` jest wspólnym stanem klienta dla paska i panelu. Serwisy itemów walidują equip po stronie serwera. Wybór zapisuje się i jest wysyłany w handshake’u `ClientReady`.

- Inventory otwiera przycisk `HUD.SideButtons.InventoryButton` i `I`; tylko w `LOBBY`. Poza nim przycisk znika, panel się zamyka i serwer odrzuca `SetLoadout`.
- Klik karty otwiera DETAILS; **ADD / REMOVE / SWAP** zmienia loadout. Przeciąganie i skróty 1–3 są dodatkowymi metodami. Sam klik ani hover nie zastępuje tego modelu.
- W DETAILS jest lokalny model w świecie przed kamerą z rzeczywistym oświetleniem; **nie ViewportFrame**. Paski POWER/RANGE/MOBILITY z ItemDefinitions.
- `I` / X zamyka; **klik w tło nie zamyka** i nie używa itemu pod spodem (decyzja 20.10).
- Kupno przy wolnym slocie automatycznie dodaje item; przy pełnym loadoucie pokazuje „ADD IT IN INVENTORY” i oznaczenie na przycisku. Nie podmienia wyboru za gracza.
- Zero sztuk nie usuwa slotu. Kolejny item nie wymaga `Slot4`.

Kontrakt panelu: [STUDIO_CONTRACT](STUDIO_CONTRACT.md). Pierwotny projekt panelu z 30.09 (`OwnedList`, `LoadoutSlots`) był zastąpiony w implementacji — nie budować go ponownie. Testy wszystkich metod wyboru są w TESTY.

## Wniosek designowy: najwyższe dachy i lawa

Decyzja Kacpra 22.09: balans końcówki ocenić z prawdziwymi graczami. Stare wyliczenia od Y −14,75 i podziału na fazy są historyczne. Aktualna krzywa produkcyjna to 80 s × średnio 1,5 stud/s = **około 120 studów przyrostu**. W Edit 23.10 wierzch startowej warstwy jest około Y 2,5, więc średnia baza kończy około Y 122,5; fizyczna tafla dodatkowo faluje. Dawny pomiar najwyższego dachu Y 109 nie był ponawiany w tym audycie.

Nie przenosić dawnych „5 s przed końcem / najwyższy dach bezpieczny” na obecną krzywą bez przeliczenia i testu. Lawa rani przez około 7 s, można z niej wypłynąć; samo zalanie dachu nie dowodzi śmierci każdego gracza. Wcześniejszy wpis o zbyt wąskim obrysie lawy też wymaga ponownego pomiaru — aktualne warstwy mają 512,75×457, inne niż w dawnym wyliczeniu.

## PLAN: OPRAWA LAWY + GRAFIKA LOW/HIGH — 27.10, zaakceptowany i WDROŻONY (NIEPRZETESTOWANE)

**Decyzje Kacpra (26–27.10):** tekstura tafli zostaje · poświata tylko na dolne piętro nad lawą · iskry i popiół **od startu, rosną z lawą** · wpadnięcie = **rozbryzg + dym + krótki błysk** · nowe ozdobniki tylko u klienta, sterowane ustawieniem **GRAPHICS: LOW / HIGH** · LOW wyłącza **nowe efekty lawy** (gruz i wybuchy bez zmian — jeden `Config.Graphics.Profile` zostaje) · start: **telefon LOW, komputer HIGH**, wybór gracza zapisany na koncie.

**Dlaczego to nie powrót odrzuconych trybów Ziemniak/Pełny (⛔ 08.10):** tamte zmieniały gruz, a lokalny gruz potrafił wpływać na grę (lekcja 10). LOW/HIGH dotyka wyłącznie ozdobników bez kolizji, promieni i dotyku — dwaj gracze z różnym ustawieniem grają w tę samą grę.

### 1. Ustawienie GRAPHICS
- `Config.Settings.Options.graphics = { Values = {"auto","low","high"}, Default = "auto" }`. Serwer (`SettingsService`) bez zmian — sanityzuje jak resztę; „auto” zapisuje się tylko, dopóki gracz nic nie kliknie.
- „auto” rozwiązuje **klient** (`SettingsState`), bo tylko on zna urządzenie: dotyk albo suwak grafiki Robloxa ≤ `LowQualityLevel` → LOW, inaczej HIGH. To dokładnie dzisiejsza reguła `LavaSurfaceController` — domyślnie nic się nie zmienia.
- Panel: trzeci wiersz **GRAPHICS** z LOW / HIGH (te same przyciski co reszta, atrybuty `Setting="graphics"`, `Value="low"/"high"`); podświetla się rozwiązana wartość także przy „auto”. Panel wyższy o wiersz. Stawiam przez MCP jak dotąd → Cmd+S.
- Zmiana działa od razu, bez restartu (efekty słuchają `SettingsState.onChanged`).
- Ten sam przełącznik przejmuje dzisiejsze automatyczne ograniczenie bąbli/dymu lawy na telefonie (mniej skupisk i świateł) — telefon z HIGH dostaje pełną lawę, komputer z LOW ograniczoną.

### 2. Poświata na budynkach (HIGH)
- Kilka stałych, pomarańczowych PointLightów tuż nad taflą wokół kamery, na siatce (żeby nie pływały za kamerą; zmiana oczka = zgaszenie i zapalenie, bez przeskoku).
- **Range ≤ 12** (reguła 21.09: Range = przebicie stropu; ~1 kondygnacja) — mocniej = Brightness. Bez cieni.
- Bramka jak ambient: lawa nad ulicą (`MinSurfaceY` + histereza) i kamera nad taflą. LOW: brak.

### 3. Iskry i popiół (HIGH)
- Jedno pudło emisji przy tafli wokół kamery: świecące iskry lecą w górę, szary popiół unosi się wolno i dryfuje.
- **Ilość rośnie z wysokością lawy** (mało na starcie rundy, najwięcej w końcówce).
- **Particle nie kolidują z geometrią**, więc o zasięgu decyduje czas życia × prędkość: w kanale (przed ulicą) wznoszą się najwyżej ~5 studów i zostają pod jezdnią (prześwit kanału 6); nad ulicą najwyżej ~1 kondygnację — tyle samo co poświata. Dzięki temu „od startu” nie przebija ulicy i nie sypie popiołem do pokoi wyżej.
- Kamera pod taflą (widok z wnętrza lawy) → wyłączone. LOW: brak.

### 4. Wpadnięcie do lawy (HIGH)
- Klient sam wykrywa, że czyjaś postać w pobliżu kamery wpada stopami pod taflę **z prędkością w dół** (wolne zalanie przez rosnącą lawę = bez efektu; wyskok i ponowne wpadnięcie = cooldown na postać).
- Rozbryzg kropli lawy, kłąb dymu i krótki błysk światła (Range ≤ 12) — z puli kilku gotowych zestawów, bez tworzenia obiektów w trakcie gry, bez remote'ów.
- Serwerowy „death poof” przy śmierci w lawie zostaje bez zmian (widzą go wszyscy). LOW: brak rozbryzgu.

### Gdzie co siedzi
- `SettingsState` — rozwiązanie „auto”; `SettingsController` — podświetlenie rozwiązanej wartości.
- `LavaSurfaceController` — ambient + poświata + iskry/popiół (to wszystko jest „lawa wokół kamery”, wspólna bramka i wysokość fali).
- Nowy `LavaSplashController` — wpadnięcia (zdarzenia postaci, osobny powód do zmiany).
- Liczby: `Config.Lava.Glow`, `Config.Lava.Air`, `Config.Lava.Splash`.
- Każdy lokalny part: `CanCollide/CanQuery/CanTouch = false` (lekcja 10).

### Do sprawdzenia przez Kacpra po wdrożeniu
FPS na telefonie przy HIGH, czy poświata nie wychodzi piętro wyżej, czy iskry nie wylatują nad ulicę w kanale, przełączanie LOW/HIGH w trakcie rundy.

## PLAN: STEROWANIE NA TELEFONIE — 28.10 (bramka premiery 6.11)

**Decyzje Kacpra (28.10):** okrągłe przyciski w stylu slotów paska, z napisami, stawia agent przez MCP · **SPRINT = trzymanie** (jak Shift) · **most: dotknij miejsce → duch tam staje, ROTATE obraca, BUILD stawia** · **RPG: przycisk AIM** (zoom + celownik, przełącznik — kciuk musi być wolny do obracania kamery), **FIRE** strzela w środek celownika.

Bez zmian (już działa dotykiem): bomba, hak, napój i rzut C4 = dotknięcie ekranu (`Tool.Activated`), odpalenie C4 = istniejący `HUD.Detonator`.

- **Jeden właściciel przycisków:** nowy `TouchControlsController` — tryb dotyku, ułożenie, wciśnięcie/puszczenie, podświetlenie. Akcje zostają u właścicieli mechanik (`MovementController`, `PushController`, `BridgeController`, `RpgController`): rejestrują się przez `bind` i same mówią, kiedy ich przycisk ma sens (`setShown`). Bez nowych remote'ów — serwer waliduje jak dotąd.
- **Tryb dotyku = widoczne sterowanie dotykowe Robloxa** (`PlayerGui.TouchGui`); bez niego: `TouchEnabled` i brak klawiatury. PC nie widzi przycisków.
- **Ułożenie wokół przycisku skoku Robloxa**: klaster przypięty do środka `JumpButton` (telefon 70 pt, tablet 120 pt w innym miejscu — stałe pozycje nachodziłyby na skok na tablecie). Bez `TouchGui` — pozycja zapasowa ze Studio.
- **Puszczenie liczone na tym samym dotyku** (stan `InputObject`), nie na wyjściu palca z przycisku — zsunięcie palca nie zostawia „wiecznego sprintu”. Schowanie przycisku w trakcie trzymania = puszczenie.
- **Most na dotyku:** duch najpierw na środku ekranu (celowanie kamerą), dotknięcie świata (`TouchTap`, nie przeciągnięcie kamery) przypina go w tym miejscu; BUILD stawia tam, gdzie stoi duch. PC bez zmian.
- `HUD.Detonator` przesunięty wyżej (Y 0,55 → 0,40): na telefonie zajmował miejsce nad skokiem, gdzie stoją BUILD/FIRE.

Do sprawdzenia przez Kacpra: TESTY → „Telefon”.

## Dalsze kierunki — do wyboru Kacpra

1. Przebieralnia i sklep kosmetyczny — **26.10: rozpoczęta implementacja na polecenie Kacpra**, ustalenia i realizacja w [COSMETICS_PLAN](COSMETICS_PLAN.md), gotowość w STATUS. Wejście przez istniejącego ClothesShop.NPC i przycisk garderoby. To nowy system posiadania/zakładania i assetów, nie samo drugie okno sklepu.
2. Akcesoria: briefy w [AKCESORIA_PROMPTY](AKCESORIA_PROMPTY.md). Modele/pomysły nie oznaczają działającego systemu.
3. Daily rewards od nowa jako UI (stary system usunięty).
4. Monetyzacja: oferta VIP/gamepass/dev products — brak zatwierdzonej tu implementacji/oferty.

**Pancerze / TRZY PUŁAPKI:** dawny plan bonusów do HP/ruchu zachowano w archiwum badawczym; nie jest zatwierdzonym obowiązkiem v1.0. Gdy Kacper wróci do niego, najpierw decyzja o wpływie na balans i kosmetyce oraz zgodność anti-cheata, obrażeń i skalowania MaxHealth. Lawa ma zabijać po tym samym czasie kontaktu; nie stosować do niej redukcji pancerza bez nowej decyzji.

Poza v1.0 pozostają m.in. voting map, lobby parkour, pożary jako mechanika, trzęsienia, blackout, bounty, kradzież monet, king zone, niewidzialne trapy, łamliwe podłogi, windy, tunele, gejzery lawy. Nie przywracać eventów „kule ognia / wiatr” jako obowiązkowej pozycji release’u na podstawie dawnego planu Day 6.

## Badania i odrzucone podejścia

Pełne opisy prób, tabel pomiarów i pierwotnych planów zachowane w [archiwum ROADMAP sprzed audytu](archive/2026-10-23/ROADMAP.md): rig R15, śliski movement, wygląd, pancerze / „TRZY PUŁAPKI”, historia endgame i loadoutu. Przed diagnozą sprawdzić historię, ale o aktualnym stanie rozstrzygają kod, STATUS i potwierdzenia Kacpra. Obowiązująca lista „nie proponować ponownie” i lekcje są w [zasadach](CLAUDE.md).
