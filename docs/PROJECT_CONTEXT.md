# ESCAPE LAVA — kontekst projektu (dla asystenta)

> Dokument dla asystenta pomagającego w organizacji pracy (TODO, planowanie, decyzje).
> Celowo bez szczegółów kodu — od logiki gry jest Claude Code w repo.
> Stan na: 2026-10-10.

---

## Czym jest ta gra

**ESCAPE LAVA** — gra na Roblox, arcade survival. 15-20 graczy na serwerze. Lawa zalewa
mapę od dołu coraz szybciej, gracze uciekają w górę po wieżowcach miasta ("Downtown"),
kupują itemy (bomby do wysadzania przeciwników i terenu, mosty do budowania przepraw,
hak do wciągania się na dachy),
spychają się nawzajem (klawisz F) i walczą o przetrwanie do końca rundy.

**Pętla gry:** Lobby (15s zakupy) → odliczanie (5s) → runda (~80s: lawa przyspiesza w
4 fazach) → nagrody → powrót do lobby. Cała pętla mieści się w ~2 minutach — celowo,
pod klipy na TikToka.

## Po co ten projekt (cel biznesowy)

- **Warm-up i generator budżetu** pod większą grę (Sword RPG). To NIE jest projekt-portfolio
  na lata — ma szybko wyjść i zarabiać Robuxy.
- Plan: ~7-14 dni produkcji → launch → monetyzacja (gamepassy VIP, dev producty) →
  marketing czysto organiczny na TikToku (zero płatnych reklam).
- KPI z GDD: D7 retention 8%, ARPU 25 R$, 30k wizyt w miesiąc.
- Skala docelowa: **kilkuset graczy jednocześnie** (dziesiątki serwerów) — wszystkie
  decyzje techniczne są podejmowane pod tę skalę.

## Kto robi co

| Osoba | Rola |
|---|---|
| **Kacper** (16 lat, solo dev, po Kaucja Simulator ~12k wizyt) | Buduje w Roblox Studio: mapę, lobby, punkty spawn, UI (wygląd), modele/assety/dźwięki. Testuje. Decyduje o designie. Max 2-3h dziennie. |
| **Claude Code** (AI w repo) | Cała logika gry w kodzie: serwisy, mechaniki, anti-cheat, zapis danych, VFX, skalowanie UI. Pilnuje jakości pod skalę. |

Zasady współpracy:
- Claude pyta o decyzje designowe zanim koduje; Kacper nie musi dotykać kodu.
- **Testy w grze robi wyłącznie Kacper** (ustalone 20.09). Claude nie odpala Play sam —
  dostarcza kod i **listę rzeczy do sprawdzenia**, a nie własne „działa". Powód: jego
  automatyczny test dwa razy dał fałszywy wynik (mierzył życie już po obrażeniach
  z poprzedniego upadku, i czytał log ze starej sesji), a do tego przerywał Kacprowi
  jego własne testy w połowie. Podglądanie gry przez MCP zostaje — to się sprawdzało
  (pomiary mapy, sprawdzanie czy kod w ogóle dojechał do Studio).

## Co jest GOTOWE (z perspektywy gracza)

- **Pełna pętla rundy**: lobby → odliczanie → runda z lawą przyspieszającą w fazach →
  nagrody → restart. Mapa naprawia się sama po każdej rundzie.
- **Bomba** (50$): rzut, odliczanie z migającym lontem, rani i odrzuca graczy (ragdoll),
  zabójstwa nagradzane kasą — a od 11-12.08 **znowu wybucha i niszczy mapę** (system
  destrukcji, patrz TODO punkt 0). Ściany pękają na nieregularne kawałki, duże płyty zostają
  jako platformy, a kto stoi za ścianą, dostaje słabiej. **Od 23.09 (v3, czeka na test)**:
  drobny gruz i meble (wieszaki, krzesła, skrzynie) padają już tylko „u gracza” — cały mebel
  przewraca się i rozsypuje, leży chwilę i gaśnie; ranią i służą za platformy tylko duże
  płyty. Grafika: **jeden profil dla wszystkich** (od 08.10 — wcześniej dwa tryby, Ziemniak
  i Pełny, usunięte decyzją Kacpra; profil to środek obu, gruz leży ~10 s).
  Gruz „u gracza” nie ma kolizji — przechodzi się przez niego, więc ilość gruzu zmienia
  wyłącznie obraz, a wszyscy grają dokładnie w tę samą grę.
  **Od 24.09 pomarańczowy budynek działa na nowej destrukcji (v4, czeka na ponowny test)**:
  bomba wycina w ścianie czy stropie prostokątną dziurę, kolejne bomby w tę samą konstrukcję
  osłabiają ją, aż się skruszy, a gdy część budynku straci podparcie — spada naprawdę, grupami,
  piętro po piętrze, i da się na niej jechać. Duże bryły zostają jako nowe platformy do końca
  rundy, drobne znikają po kilku sekundach. Meble i pudła padają w całości. Pierwszy test 24.09:
  „takto wszystko działa raczej” + cztery usterki, poprawione. **25.09 test „dymny” (Claude sam
  rzucał bomby w Studio) pokazał, że większość pięter tylko udawała, że spada** — fizycznie
  zaczepiały o resztki przeciętych słupów i skruszonych belek, więc budynek stał nad zburzonym
  parterem. Po poprawkach 14 z 24 brył spada naprawdę, a te, które mimo wszystko utkną, spadają
  „u gracza” (nic nie wisi w powietrzu). Jazda na spadającym dachu i stropie działa. Jazda na
  spadającym piętrze liczy się od 26.09 jak zwykły upadek (Twoja decyzja — zastępuje tę z 25.09
  o połowie obrażeń): dopóki stoisz na bryle, nie boli, boli dopiero spadnięcie z niej, a bryła
  pod Tobą nigdy Cię nie przygniata (wcześniej lądowanie stropu potrafiło zabić „przygnieceniem”
  po małym upadku; potwierdzone w teście 26.09). Twoje decyzje z 25.09: belka pod przeciążonym
  filarkiem pęka, kikuty słupów spadają razem ze
  stropem. Po Twoim teście 25.09: leżące po zawaleniu bryły da się znowu rozwalać bombą (wybija w nich dziurę), a osiadłe bryły przestały działać jak taśma pod nogami. Gruz, przez który się przechodzi (bez kolizji), jest teraz ciemnoszary i posiekany na kawałki zamiast wielkich klocków; ekran nie trzęsie się już przy każdym walącym się kawałku; po śmierci leżysz ~2 s jako ragdoll, zanim wrócisz do lobby. Drabina i długie listwy (26.09 wieczór, Twoje decyzje): bomba wycina tylko trafiony kawałek listwy, a listwa zostaje, dopóki dotyka czegoś, co stoi — drabina trzyma się piętra, które ją jeszcze podpiera, a szczeble nie wiszą w powietrzu (potwierdzone w Twoim teście 26.09 wieczorem). Bryły, które „wiszą chwilę, potem znikają”, są następne. Zmiany z 25.09 potwierdziłeś w Play 26.09 („wszystko git działa”). **26.09 gra z kolegą** wyłapała trzy błędy — poprawki potwierdzone w Twoim teście 26.09 wieczorem: hak dało się odpalić w trakcie ragdolla i wystrzeliwało postać w kosmos (teraz w ragdollu hak nie działa i przerywa lot); martwy kolega wisiał pod mapą aż do następnej rundy (błąd z dnia wcześniej — po 2 s ragdollu nie zawsze wracało się do lobby); czasem bomba kolegi nie robiła Ci nic (przyczyna jeszcze nieznana — gra od teraz pisze w Output, czemu bomba kogoś pominęła). Do tego 26.09 rano cała gra leżała przez literówkę w ustawieniach lawy (`MaxY = 250ś`) — poprawione na 250. Twoja decyzja z 26.09 wieczorem: **odradzamy zawsze** — śmierć poza rundą (np. reset w lobby) też kończy się powrotem do lobby po ~2 s ragdolla; wcześniej trup leżał do startu albo końca rundy (potwierdzone w teście). Test obciążenia 26.09: 5 wybuchów naraz serwer wytrzymuje. **26.09 noc: GreenBuilding przechodzi na nową destrukcję** (w kodzie, sprawdzone na kopiach, NIEPRZETESTOWANE w grze) — Twoje decyzje: tunel torów przez budynek spada razem z budynkiem, a **kawałek torów nad walącym się budynkiem spada razem z nim** (w obu budynkach), reszta torów zostaje. **Rekwizyty (26.09 noc, Twoje decyzje; w kodzie, nieprzetestowane)**: wieszaki, rośliny, paczki, kosze, krzesła i TV w zasięgu dziury od bomby po prostu znikają w obłoku pyłu (bez setek kawałków — wieszaków w zielonym budynku było 37, ale prawie 2000 partów); meble (skrzynie, szafki, półki, automaty) blisko bomby rozpadają się na kawałki, które szybko znikają, a dalej są odrzucane w całości — da się na nie wskoczyć, a druga bomba je rozwala. **27.09 wieczór — AUTA WYBUCHAJĄ** (Twoja decyzja „wybucha + ogień”; w kodzie, nieprzetestowane): bomba blisko auta → auto wybucha razem z nią (słabiej niż bomba, rani i odrzuca graczy obok, kill dla rzucającego), rozlatuje się na kawałki i płonie przez ~6 s (ogień to sam efekt — nie rani); auto stojące tuż obok może wybuchnąć łańcuchowo. Wcześniej auta w ogóle nie reagowały — były zablokowane przed destrukcją. **27.09: CAŁE MIASTO jest na nowej destrukcji** — wszystkie 10 budynków wali się piętrami (w kodzie, sprawdzone na kopiach, NIEPRZETESTOWANE w grze); stary system zostaje tylko poza budynkami (ulice, samochody, latarnie). Kolejność: na nową destrukcję przechodzą też OrangeKebab, CyanOffice i OldBuilding2 (Twoja decyzja: najpierw te, które stoją bez poprawek); pozostałe 5 budynków po Twoim teście GreenBuildingu. Wszystkie krzesła znikają jak wieszaki, biurka w biurowcu są meblami (odpychane, druga bomba je rozwala). **28.09 (w kodzie, NIEPRZETESTOWANE w grze)**: (1) rzeczy stojące tylko na meblu (TV na szafce, produkty na półce) spadają razem z nim, a duże dekoracje (deski rusztowania, lady) spadają, gdy nic ich już nie trzyma — wcześniej wisiały w powietrzu (TV i tak znika z obłokiem, bo należy do drobiazgów); (2) kawałki skruszonej ściany są teraz zwykłym gruzem budynku — bomba je tnie, małe znikają po ~4 s; (3) walące się bryły przestają „wisieć chwilę i znikać” (w Twoim teście 28.09 utknęło 10 z 38) — spadają od razu, nawet jeśli opierają się o róg stojącej belki (Twoja decyzja), a te, które mimo to utkną, są odblokowywane i spadają dalej prawdziwą fizyką (da się na nich dalej jechać).
- **Most** (100$): budowanie przeprawy z podglądem "ducha", obracanie. **Od 01.10 most ma
  fizykę od razu po postawieniu** (Twoja decyzja): leży na tym, na czym go położysz, działa
  tylko oparty o coś oboma końcami (np. między dwoma dachami), wysunięty nad przepaść się
  przechyla i spada, a bomba odrzuca cały most (sabotaż PvP). Celowanie w lawę dalej działa
  jak celowanie w podłogę, ale nad lawą podgląd jest czerwony i mostu nie da się tam postawić
  (inaczej utonąłby, a 100$ przepadłoby za nic).
- **Gęsta lawa (01.10, Twoja decyzja)**: wpadasz i powoli opadasz, ruszasz się jak w miodzie;
  trzymany skok powoli wyciąga w górę, a przy powierzchni wybija z lawy, żeby wejść na brzeg.
  Pod powierzchnią ekran jest gęsty i pomarańczowy, nic nie widać na wylot. Ciągle boli
  (7 s do śmierci), ale skok do lawy z dachu nie łamie nóg o dno.
- **Hak** (40$, 22-23.09, trzeci item) — celujesz w ścianę albo dach w zasięgu 70 studów,
  klikasz i lecisz **po łuku prosto w to miejsce**, lądując trochę nad punktem trafienia.
  Trafisz tuż pod krawędzią dachu → przeskoczysz na dach. Jedno użycie = jeden zaczep.
  Zjazd hakiem w dół boli przy lądowaniu jak skok z tej wysokości (Twoja decyzja).
  **Przetestowane w Play** (odczucie lotu i przypadki brzegowe, 23.09). Model lotu przeszedł cztery wersje, bo każda
  kolejna naprawiała jedną rzecz kosztem poprzedniej: najpierw wywalało do góry, potem
  leciało dobrze, ale przelatywało przez punkt, potem dolatywało, ale po sztywnej prostej.
  Dopiero łuk prowadzony do punktu spełnia wszystko naraz.
  ⚠️ **Nie widać go w pasku** — pasek ma tylko 2 sloty. Działa z klawisza 3.
- **Push (F)**: spychanie przeciwników z cooldownem 2,5 s i zamachem 0,15 s (customowa animacja oburącz; pozostały ruch domyślny) — kill credit jak wpadną w lawę.
- **Kasa**: zbierana z mapy (przyciąganie magnetyczne + animacja lotu ze złotym trailem),
  za zabójstwa (25$), za przetrwanie rundy (100$), popupy "+10$", licznik kasy w HUD
  w Twoim stylu (cyfry-obrazki ze studs zostały wyłączone 11.08, bo wyglądały źle).
- **Sklep w nowym lobby** (20.09, przetestowane) — po przebudowie lobby sprzedawca broni
  stoi w swoim straganie, a wystawa z itemami przeniosła się do osobnego pomieszczenia,
  do którego zjeżdża sama kamera (Ty zostajesz przy sprzedawcy, więc kilka osób może
  kupować naraz). Kamery celują w bombę i w plan mostu. Dodanie kolejnego itemu to
  postawienie modelu i markera obok niego — kod sam je paruje po tym, co stoi naprzeciw,
  więc nazwy markerów nie mają znaczenia. Na dole panel z nazwą, ceną, opisem i przyciskiem
  KUP; przewijanie strzałkami / A-D / scrollem; zakup weryfikowany odległością od
  sprzedawcy, więc nie da się kupować w trakcie rundy. Sprzedawca ubrań na razie nic nie robi.
- **Postacie: jednolity rig + losowy wygląd** (21.09) — wszyscy wchodzą teraz jako ta sama
  postać od gry (nie własny avatar), a losowany jest kolor skóry, koszulki i spodni plus
  krój: rękaw krótki albo długi, nogawki długie albo szorty. Zestaw przypisywany raz
  i zapamiętywany. To jest pierwszy krok systemu skinów — sklep będzie potem podmieniał
  pojedyncze elementy tego samego zapisu.
  Zapis działa też w Studio (sprawdzone 21.09 — kasa przeniosła się między sesjami).
  **Twarz: widoczna i poprawna** (potwierdzone 22.09) — głowa ma twarz wbudowaną. Gdyby
  twarze miały być skinem na sprzedaż, trzeba będzie podmienić głowę na klasyczną, kanciastą —
  ta decyzja wraca dopiero przy sklepie kosmetycznym.
- **Ragdoll naprawiony u źródła** (21.09) — postać leci po bombie jak trzeba. Przyczyną
  „trzepania" był nowy typ szkieletu postaci, którego nie znosi używany przez nas ragdoll:
  na jednym ciele pracowały dwa zestawy stawów naraz. Szkielet został przerobiony na starszy
  typ i problem zniknął (potwierdzone w Play). **Zapisz plac (Cmd+S)** — ta zmiana siedzi
  w pliku placu, nie w kodzie. „Śliskie" sterowanie też zniknęło (potwierdziłeś 23.09).
  **Obracanie głowy za kamerą działa od 23.09** (potwierdziłeś). Wcześniej nie działało nigdy —
  i nie przez szkielet: kod obracał głowę w sposób, który animacje postaci od razu nadpisywały.
- **Twoje modele w grze** (20.09, przetestowane) — bomba, którą trzymasz w ręce, jest tą
  samą bombą, która leci i wybucha; w trybie budowania trzymasz plan; most to Twój model
  z 12 desek (od 01.10 spawanych w jedną bryłę z fizyką). **Most jest większy niż wcześniejszy zastępczy
  (13.25 zamiast 10 długości) — tak miało być.** Rozmiar bierze się z modelu, więc gdybyś
  kiedyś chciał inny, skalujesz model w Studio i kod sam się dostosuje.
- **Spawn w lobby naprawiony** (20.09) — punkt spawnu przyjechał ze Studio niezakotwiczony
  i po prostu spadał przy starcie gry, zabierając ze sobą miejsce, w które gra teleportuje
  graczy. Kod kotwiczy go teraz sam i mówi o tym w logu.
- **Hotbar** z equipem itemów (klawisze 1-5, białe podświetlenie wybranego slotu).
  ⚠️ W Studio są tylko **2 sloty** — każdy kolejny item potrzebuje kolejnego (skopiuj Slot2).
- ~~Daily rewards~~ — **skasowane 12.09**, bo stare UI się nie podobało. Do zrobienia od nowa.
- **Ruch**: sprint (Shift) ze staminą, kamera 3rd person z płynnym wygładzaniem,
  dynamiczny FOV, wstrząsy ekranu przy trafieniach, kurz przy lądowaniu. **Kamera zza
  ramienia** (23.09): kamera nad prawym ramieniem, postać po lewej stronie ekranu, jak
  w Fortnite (porównałeś obie strony — „prawa zostaje"). Kamera zatrzymuje się na ścianach:
  plac miał ustawiony tryb, w którym ściany zamiast zatrzymywać kamerę robiły się przezroczyste
  (x-ray, dało się podglądać przez mury) — naprawione i potwierdzone 23.09. Głowa i lekko tułów
  podążają za kamerą, widać to też u innych graczy (od 23.09).
- **Klimat**: lawa z unoszącymi się iskrami i dymem, "żar" na ekranie gdy gracz jest
  nisko nad lawą, słup pary przy śmierci w lawie.
- **Lawa rani zamiast zabijać od razu** (21.09, Twoja decyzja) — 7 sekund kontaktu zabija,
  wyjdziesz z lawy, przestaje boleć. Zmienia lawę ze ściany śmierci w zagrożenie, przed którym
  da się uciec. Przy okazji zdrowie w całej grze przestało się samo regenerować (inaczej
  krótkie wejścia goiłyby się między sobą).
- **Szyby się tłuką** (21.09) — 367 szyb w 9 budynkach. Bomba tłucze średnio ~17 szyb
  w promieniu 35 studów, także na sąsiednich budynkach; im większa szyba, tym więcej i większych
  odłamków. Wcześniej nie tłukła się żadna, bo wszystkie szyby miały zły materiał.
- **Latarnie i sygnalizatory znowu świecą** (21.09) — zaznaczenie całej mapy i nadanie jej
  jednego materiału **po cichu** zgasiło 36 latarni i 150 żarówek sygnalizacji i zamieniło szyby
  w zwykłe ściany. Nic nie znikało, więc nikt tego nie zauważył. Naprawione skryptami, które
  można puścić ponownie po każdej takiej operacji.
- **Lawa jako stos warstw** (16.09, Twój pomysł) — zamiast jednej płaskiej tafli stos:
  nieprzezroczysty spód i półprzezroczyste warstwy nad nim, każda w innym kolorze.
  To pierwsze podejście do wyglądu lawy, które nie próbuje namalować głębi na płasko,
  tylko ją naprawdę ma — plus warstwy falują jedna względem drugiej i przesuwają się
  różnie przy ruchu kamery. Stos stoi już w Studio (**zapisz plac Ctrl+S!**), kod
  sprawdzony w Play. Liczba warstw jest dowolna: dołożysz czwartą w Studio i zadziała
  bez zmian w kodzie. **Stan na 23.09 (zmierzony)**: stos ma **dwie** warstwy — spodnią
  usunąłeś, a nieprzezroczystym spodem jest teraz środkowa — i leży w kanale pod ulicami:
  lawa startuje z wysokości ≈ 2,5, nie jak wcześniej z −14,75.
- **Obrażenia od upadku + ragdoll** (16-19.09) — spadek z wysokości rani, a od 30 studów
  przewraca postać, i to **jeszcze w locie**, żeby wywrotka wypadła na uderzeniu, a nie po
  nim. Zepchnięcie kogoś z dachu liczy się jako Twoje zabójstwo. ⚠️ **Przepisane 19.09 od
  zera i NIEPRZETESTOWANE** — zgłosiłeś dwa błędy (wyrzut bombą bez obrażeń, drugi upadek
  bez obrażeń) i oba miały jedną przyczynę, którą sam wcześniej wprowadziłem. Lista pięciu
  rzeczy do sprawdzenia jest w CLAUDE.md w sekcji STATUS. Zjazd hakiem w dół liczy się
  jak zwykły upadek z punktu startu — hak wyłącza tylko przewracanie w połowie lotu.
- **Nowe oświetlenie** (16.09) — stare było rozjaśnione „ambientem" tak mocno, że cienie
  miały prawie ten sam kolor co światło i wszystko wyglądało płasko, a filtr koloru
  próbował to ratować kontrastem i niebieskim odcieniem, który gryzł się z pomarańczem
  lawy. Teraz: ciepłe słońce, chłodne cienie, lekka mgiełka dystansu (dalsze wieżowce
  delikatnie blakną, więc miasto czyta się jako wysokie) i świecenie tylko tego, co
  naprawdę gorące. Słońce jest widoczne na niebie. Skybox bez zmian. Gdyby coś nie
  siadło — w repo leży plik cofający wszystko jedną komendą.
- **Oprawa lawy** (14-21.09) — powierzchnia przewija się (Ty dajesz teksturę, kod ją
  animuje), tafla faluje, wypychają się z niej bąble i pękają z iskrami, ciepłe światła
  podświetlają dolne piętra, a tam gdzie lawa podchodzi pod ulicę unosi się para. Od 21.09
  **zapala się dopiero, gdy lawa wyjdzie na ulice** — dopóki siedzi w kanale pod miastem, 
  efekty przebijałyby przez jezdnię. Tekstura powierzchni jest po Twojej stronie.
- **Pasek staminy przy postaci** (12.09): nie element HUD, tylko pionowy wskaźnik unoszący
  się obok Twojej postaci w świecie — widzi go **tylko właściciel**. Pokazuje się sam przy
  sprincie i chowa po naładowaniu, ze sprężystą animacją; kolor idzie od niebieskiego przez
  żółty do czerwonego w miarę ubywania sił.
- **HUD**: komunikat „YOU KILLED <nick> +25$” dla zabójcy i „YOU SURVIVED! +100$” dla każdego ocalałego (na środku, tylko dla siebie), paski cooldownów; **pełne skalowanie na każdy
  monitor** (projekt w px przy 1440p, reszta skaluje się automatycznie, elementy przypięte
  do krawędzi/rogów ekranu).
- **Zaplecze**: zapis postępu graczy (kasa/itemy/winy/wygląd) odporny na awarie,
  tab-leaderboard (Cash + Wins), anti-cheat, rate limity, walidacja wszystkiego po
  stronie serwera.
- **Audyt techniczny (11.08)** — przegląd całego kodu serwera pod kątem błędów i skali.
  Najważniejsze z tego, co zostało naprawione, w języku skutków dla gracza:
  - gracz przeskakujący między serwerami mógł **stracić do minuty postępu** (kasa, zakupy,
    winy) — zapis i odczyt danych nie były ze sobą uzgodnione;
  - jeden błąd w trakcie rundy potrafił **zostawić serwer w rozbitym stanie** (mapa się nie
    odbudowywała, nagrody nie były wypłacane) aż do restartu;
  - anti-cheat na speedhack **nie działał w ogóle** — sprawdzał wartość, której serwer
    fizycznie nie widzi; zmierzone i przepisane na pomiar realnie przebytej drogi;
  - lawa i zbieranie kasy generowały **tysiące zbędnych zdarzeń na sekundę**, gdy na mapie
    było dużo gruzu — czyli dokładnie wtedy, gdy serwer i tak jest najbardziej obciążony;
  - obracanie głów postaci kosztowało ~5000 wiadomości sieciowych na sekundę za sam efekt
    wizualny.

## TODO (priorytety)

**Stan 08.10: Kacper TESTUJE w Play** (lista `docs/TESTY.md`) i zgłasza na bieżąco — poprawki z 08.10 opisane w „Stan na 2026-10-08” na końcu. Zostaje: stały test destrukcji T1-T7 dwa razy pod rząd (zamrożenie destrukcji), potem loadout, start klienta, anty-cheat, nowe itemy, telefon. **Wcześniej — TEST NOWEJ DESTRUKCJI w grze (stan 28.09).** Całe miasto jest na nowej destrukcji; do sprawdzenia w Play: zawalanie wszystkich 10 budynków, tory, rekwizyty, auta, spadające TV/deski, kawałki skruszonych ścian i czy bryły dalej „wiszą i znikają” (lista testu: `docs/DESTRUCTION_PLAN.md`, sekcje z 26-28.09). Potem z destrukcji zostaje: sprzątanie starego systemu poza budynkami, dźwięki (5 id od Kacpra) i zapis „mapy konstrukcji” w placu przed launchem. Opis niżej jest historią z 24-25.09.

**Historia 24-25.09 — NOWA DESTRUKCJA (v4): pomarańczowy budynek już w grze, czeka na ponowny test.**
Stan na 25.09: zbudowane „mapa konstrukcji” pomarańczowego budynku, dziury, osłabianie i kolaps
prawdziwą fizyką. Pierwszy test 24.09 wyłapał cztery rzeczy (górne piętra znikały zamiast spadać,
szyby wisiały w powietrzu, część gruzu lewitowała, pudła i szafki rozpadały się bez sensu) —
przyczyny znalezione, poprawki czekają na ponowne sprawdzenie. Dalej, po kolei: obrażenia dla
kogoś, kto jedzie na spadającym piętrze (dziś liczą się jak zwykły upadek, a mają być o połowę
mniejsze), test kilku bomb naraz, test z dwoma graczami i słabym internetem, potem przeniesienie
kolejnych budynków (zielony jako następny).
Kierunek ustalony 24.09. Po debacie dwóch asystentów
architektura jest zamknięta decyzjami Kacpra: budynek dostaje w Studio „mapę konstrukcji” (które kawałki
trzymają które), bomba robi dziurę dokładnie tam, gdzie wybuchła, a gdy część budynku traci
podparcie, spada prawdziwą fizyką — gracz może na niej jechać (przy lądowaniu dostaje połowę
obrażeń za przejechaną wysokość). Cały budynek da się położyć ~8 dobrze rozmieszczonymi bombami,
bez ostrzeżenia, kaskadą do dachu. Duże ruiny zostają do końca rundy jako nowe platformy.
Tryb grafiki nigdy nie zmienia tego, po czym się chodzi. Najpierw jeden budynek (pomarańczowy),
potem reszta. Szczegóły: `docs/DESTRUCTION_PLAN.md` → „v4”.
(Stare: v3 — niżej — nie był zamkniętym tematem; do czasu przełączenia budynków działa w grze.)
**Test destrukcji v3 (23.09 wieczorem, zgłoszenie „gruba ryba”)**: po teście na
telefonach z kolegami wyszło: 4 bomby naraz = lagi, przenikanie przez podłogę, komunikat „part
nie został pocięty” co chwilę, wieszaki w zielonym budynku rozlatują się i znikają. Przyczyny
zmierzone na mapie i naprawione w kodzie (szczegóły i lista testu: `docs/DESTRUCTION_PLAN.md` → „v3”).
Do sprawdzenia: wieszaki, przenikanie (także z opóźnieniem sieci w Studio), 4 bomby naraz
z kolegami, oba tryby grafiki (w trybie dev klawisz G).
**Potem — zaległe testy w Play**: pięć przypadków obrażeń od upadku (lista w CLAUDE.md).
Rozstrzygnięte 23.09: śliskie sterowanie zniknęło, hak przeszedł testy, obracanie głowy
i kamera zza ramienia naprawione i potwierdzone.
Znalezione w logu i odłożone: zaczep hakiem pod własne nogi zużywa sztukę za nic (na
produkcji strata 40$ za misklik). (Szum w logu wybuchów — naprawiony w v3.)

**Do postawienia w Studio (Twoja strona):** trzeci slot w pasku (hak jest niewidoczny),
marker kamery obok haka na wystawie (dziś kadr liczy się automatycznie). (Panel ustawień
grafiki odpadł 08.10 — jeden profil dla wszystkich.)

**A. Wizja ustalona 12.09 — kolejny duży blok pracy:**
- **Ekwipunek i loadout**: hotbar skrócony do **3 slotów**, a gracz wybiera 3 itemy
  z docelowych **6**. Sens: zmusić do decyzji (mobilność vs atak vs wsparcie) zamiast
  brania samych ułatwień w bieganiu. Daje 20 różnych zestawów.
- **Drugie stoisko — skiny**: osobny NPC, kamera przesuwa się na Twoją postać
  w przebieralni, przewijasz i kupujesz. **Uwaga: to nie jest "drugi sklep", tylko nowy
  system** (zapis posiadanych skinów, zakładanie na postać przy odrodzeniu, assety) —
  robić dopiero po loadoucie.
- **Daily rewards od nowa** jako UI.
- **Szóstka itemów WYBRANA** (22.09 — odczytana z modeli, które postawiłeś na wystawie):
  bomba, most, **hak ✅**, **RPG**, **sticky bomb**, **energy drink**. Zostają trzy.
  Żaden z nich nie nagradza kempingu na szczycie, więc obawa przy wyborze (mina, ściana)
  odpadła. Pozostałe pomysły z 16.09 w zanadrzu: lotnia, stawiana ściana, kontrolowana
  rozbiórka, trampolina, mina, zastygacz, granat grawitacyjny, zamiana miejsc.

**Decyzje podjęte 16.09 (do przekazania builderowi):**
- **Avatar: zostajemy przy R15.** Chodziło Ci o kwadratowy kształt, a nie o konkretny rig —
  i R15 to daje przez ustawienia proporcji. R6 odrzucony, bo kosztowałby trzy rzeczy:
  zepsułby obracanie głowy, przesunął próg śmierci w lawie i wymusił ponowny test ragdolla.
  Przy okazji: **wymuszenie tej samej skali dla wszystkich naprawia istniejący cichy błąd** —
  dziś gracze z różnymi avatarami mają minimalnie różny próg śmierci w lawie.
- **Skiny w v1.0 są czysto kosmetyczne.** Bonusy do gry na ubraniach odradzone: to
  pay-to-win, a do tego rozmywa Twój własny pomysł na loadout, w którym wybór 3 z 6 itemów
  ma być JEDYNĄ osią mocy. Argument za jednolitą bazą, o którym warto pamiętać: przy
  losowych avatarach kupiony skin ginie w tłumie — dopiero gdy wszyscy wyglądają tak samo,
  skin widać, a dopiero wtedy ktoś chce za niego zapłacić. Nowy gracz dostaje jeden
  darmowy skin na start.
- **Builder może zaczynać.** Obecny sklep nadaje się do dopieszczenia od razu (wygląd
  dowolny, byle nazwy obiektów zostały — lista w CLAUDE.md). Stoisko skinów też może
  powstać równolegle, choć kod do niego jest daleko w kolejce; niech buduje stoiska jako
  **powtarzalny moduł**, bo trzecie (loadout) prawdopodobnie dojdzie.
  ⚠️ **Zanim oddasz robotę: zdecyduj, gdzie ma być wybór loadoutu** (ten sam NPC co sklep,
  trzecie stoisko, czy HUD). To jedyna rzecz, przez którą builder mógłby coś przerabiać.

**B. Otwarte pytanie designowe — jak ma się kończyć runda na najwyższych dachach**:
⚠️ **Korekta z 23.09 — wcześniejszy zapis był nieaktualny i na nim oparłeś decyzję z 22.09.**
Pomiar z 14.09 mówił, że lawa kończy rundę ~3 study pod najwyższym dachem — ale liczył start
lawy od −14,75, a Ty potem przeniosłeś stos do kanału (start ≈ 2,5). Stan faktyczny przy
produkcyjnych liczbach: lawa **dochodzi do najwyższego dachu ~5 s przed końcem rundy i kończy
14 studów nad nim**. Ponieważ rani przez 7 s zamiast zabijać od razu, gracz z pełnym życiem
na jednym z dwóch najwyższych dachów **przeżyje, stojąc całkowicie zanurzony w lawie**; na
niższych budynkach już nie. Czyli pytanie nie brzmi „czy szczyt jest za bezpieczny", tylko
**„czy przetrwanie pod powierzchnią lawy jest OK"**. Decyzja „rozstrzygamy po teście z ludźmi"
dalej ma sens — teraz wiadomo, na co patrzeć.


0. **System destrukcji v2** — stary wybuch skasowany 11.08, tego samego dnia zaprojektowany
   nowy (plan zatwierdzony: `docs/DESTRUCTION_PLAN.md` w repo). Cel: topka Roblox — party pękają
   na nieregularne kawałki (dziury w ścianach), szyby sypią się z sąsiednich budynków,
   filary padają od kilku bomb z widocznymi pęknięciami, gruz przygniata graczy (kill
   "crushed"), a w etapie 4 całe sekcje budynków się walą, gdy filary padną.
   **WSZYSTKIE 5 ETAPÓW ZAIMPLEMENTOWANE (11-12.08).** Etap 1 (pękanie ścian, dziury,
   gruz-platformy, nowe VFX) przetestowany i przyjęty; zgłoszone wiszące płyty naprawione.
   Etapy 2-5 czekają na test: szyby i filary, osłona za ścianami, spadanie niepodpartych
   pięter, pękanie gruzu przy upadku, przygniecenia, kolaps całych sekcji budynku po
   filarach z ostrzeżeniem, ślady opalenia. **Zostaje: dźwięki (assety Kacpra — 5 pól
   w konfiguracji, kod gotowy) i balans po testach.**
   Do testu Kacper stawia: party Material Glass (szyby — zrobione 21.09, 367 szt.) i party
   z tagiem "Pillar". ⚠️ **Na mapie jest 0 filarów, a tagować jeszcze NIE WOLNO**: kolaps
   uznaje za „budynek” całe miasto (tak jest zbudowana hierarchia mapy) i zrzucałby party
   z całej mapy — najpierw poprawka w kodzie.
   **v3 (23.09)**: serwer trzyma tylko stan gry (dziury, resztki ścian, duże płyty), drobnicę
   i kawałki dziur animuje każdy gracz u siebie, w swoim trybie grafiki; spada tylko to, co
   wybuch realnie pozbawił podparcia; pocięta podłoga nie znika spod nóg (jest przycinana).
1. **Mapa Downtown** — NAJWIĘKSZY BRAKUJĄCY ELEMENT. Kacper buduje w Studio: 10-15
   budynków 3-8 pięter, punkty spawn (multi-spawn), markery spawn kasy. Bez mapy nie ma gry.
   **Zasady budowania POD NOWĄ DESTRUKCJĘ** (pełny kontrakt w `docs/DESTRUCTION_PLAN.md`):
   każdy part `Anchored = true`; geometria pod `Workspace.Map`; budynek = folder;
   konstrukcja ze zwykłych Part (Union/MeshPart nie pękają); szyby = Material Glass;
   filary = tag `Pillar`. Kafelkowanie 6×6 JUŻ NIEPOTRZEBNE — system tnie party w runtime,
   ściany mogą być dużymi panelami (mniej roboty, lepszy FPS).
2. **Assety Studio pod istniejące mechaniki** (kod ma fallbacki, ale docelowo Kacper
   stawia swoje): model kasy (paczka banknotów?), szablon mostu, szablony UI
   (popup kasy, paski cooldownów — do ostylowania).
3. **Monetyzacja (Day 5)**: gamepass VIP, dev producty (kup kasę za Robuxy) — do
   zaprojektowania oferta i ceny, potem implementacja.
4. **Pozostałe itemy z szóstki**: RPG, sticky bomb, energy drink — modele już stoją na
   wystawie, kod dokłada się według wzorca bomby/mostu/haka. Każdy kolejny item to też
   kolejny slot w pasku (Twoja robota w UI).
5. **Polish przed launchem (Day 6)**: dźwięki (assety = Kacper), eventy losowe
   (spadające kule ognia, wiatr) — pomysły z GDD, do decyzji czy w v1.0.
6. **Launch (Day 7)**: closed beta z ekipą → publish → TikToki (formaty z GDD sekcja 14).
   **Przed publishem cofnąć trzy ustawienia testowe** (gra krzyczy o nich w logu przy
   każdym starcie): runda wydłużona do 240 s z 3× wolniejszą lawą → z powrotem 80 s; tryb
   dev z nieskończonymi itemami **dla wszystkich graczy** → wyłączyć; minimum graczy 1 → 2.
   Potem test pełnej pętli na żywym serwerze.
7. **Test pod obciążeniem** (przed/tuż po launchu): audyt kodu jest zrobiony (11.08),
   zostaje sprawdzenie na żywym serwerze z ekipą — zapis danych przy 20 graczach,
   wyłączanie serwera. Koszt kilku bomb naraz: pierwszy test z kolegami (23.09) pokazał
   lagi → przebudowa v3 tego samego dnia; potwierdzenie = kolejny test z ekipą.

## Czego ŚWIADOMIE NIE robimy w v1.0

Voting map, lobby parkour, pożary, trzęsienia, blackout, bounty, kradzież monet, king
zone, niewidzialne trapy, łamliwe podłogi, windy, ukryte tunele, gejzery lawy.
Każdy pomysł "a może dodamy..." → odpowiedź brzmi: **po launchu, nie teraz**.

## Kluczowe zasady designu (nie łamać)

- **Szybko i dynamicznie**: runda ~80s, lobby 15s. Nie wydłużać bez testów z graczami.
- **Wszystko clip-friendly** (TikTok): krótkie rundy, efektowne momenty (eksplozje,
  wygrane, wpadki do lawy).
- **Server ma zawsze rację**: klient niczego nie decyduje (anti-cheat).
- **Gracz nie może być wkurzony**: brak sztucznych opóźnień, feedback na każdą akcję
  (dźwięk/efekt/animacja), self-recovery z każdego złego stanu.

## Fakty techniczne (minimum dla orientacji)

- Kod w repo Git (`~/escapelava`, macOS), synchronizacja do Roblox Studio
  przez **Rojo** (`rojo serve` + plugin Connect w Studio). Kod źródłowy = repo,
  wygląd/mapa = plik place w Studio (zapisywać Ctrl+S!).
  **Gdy coś "nagle przestało działać", najpierw sprawdź czy Rojo serwuje.** Padnięty
  `rojo serve` w trakcie edycji zostawia w Studio plik w połowie zaktualizowany, a objawy
  wyglądają dokładnie jak błąd w logice (11.08 kosztowało to sesję diagnozowania lawy,
  która "przestała zabijać").
- Wszystkie liczby balansu (ceny, czasy, siły, nagrody) w JEDNYM pliku konfiguracyjnym —
  zmiany balansu nie wymagają grzebania w logice.
- Zapis graczy: DataStore z pełnym zabezpieczeniem (atomowość, retry, session lock,
  zapis przy zamknięciu serwera).
- Ragdoll: gotowy toolbox (ARTFVL) — folder w Workspace, nie ruszać.
- **Commitować po każdej skończonej rzeczy.** 13-22.09 dziewięć dni pracy (lawa, oświetlenie,
  upadki, postacie, szyby) leżało tylko na dysku, poza historią — zabezpieczone jednym
  commitem 22.09. Jeden padnięty dysk i nie byłoby czego odtwarzać.
- Dokumentacja dla AI kodującego: `CLAUDE.md` w repo (zasady i aktualny stan) + folder `docs/`
  (architektura kodu, kontrakt Studio, roadmapa, historia). Podzielona 23.09 — wcześniej jeden
  plik ~185 KB ładowany w całości na start każdej sesji, z 17 wewnętrznymi sprzecznościami.

## Kluczowe liczby (balans)

- Runda: 5s spawn + 20s easy + 20s mid + 20s hard + 15s endgame = 80s. Lobby 15s.
- Lawa: 0.6 → 1.2 → 2.0 → 3.0 stud/s. Kontakt z lawą zabija po 7 s (nie od razu).
  ⚠️ Obecnie testowo: runda 240 s i lawa 3× wolniej — do cofnięcia przed launchem.
- Bomba 50$ (odpalenie 2.5s, zasięg rażenia graczy 22, niszczenie terenu 24, szyby 35),
  most 100$ (od 08.10 dłuższy: 16 studów), **hak 40$ (zasięg 70)**, push F co 4s.
- Nagrody: przetrwanie 100$, kill 25$, kasa z mapy 10$/szt. (Daily skasowane 12.09 —
  do zrobienia od nowa.)
- Start gracza: 100$ na dzień dobry.

## Stan na 2026-10-10

- **Potwierdzone w Play**: drabiny, jeden profil grafiki, mosty + ghost, gęsta lawa. Eksplozje „raczej git, nie na 100%” — do stałego testu destrukcji.
- **Nowe UI z projektu Kacpra w Figmie** (https://www.figma.com/design/QT4JMeE6jssxdNPzJMmhNG/Untitled?node-id=0-1). Zasady Kacpra: czcionka zawsze Fredoka; wszystko skaluje się z ekranem; pod każdym tekstem czarny cień przesunięty w lewo i w dół; UI to obiekty w Studio, nie kod; ostre przy każdej skali (żadnych rozmytych obrazków). Zrobione: licznik kasy (zielony napis z przesuwającym się połyskiem, ikona banknotów), przy każdym zarobku banknoty lecą ze środka ekranu do licznika — licznik podskakuje, ikona się przechyla, wybuchają iskierki, liczba płynnie rośnie (popup „+10$” usunięty); pasek 3 slotów z ikonami itemów i angielskimi nazwami (Bomb / Bridge / Grapple). Czeka na ocenę Kacpra. Dalej z Figmy: czas ROUND/LOBBY, komunikat zabójstwa, przyciski SETTINGS/INVENTORY, panel ustawień (duży szary prostokąt), szkic INVENTORY/DETAILS.
- Poprawki 08-09.10: latarnie i sygnalizatory padają w całości, twarde ruiny, Studio nie wisi po Stop (jeden końcowy zapis gracza) — czekają na test.

## Stan na 2026-10-08

Kacper zaczął test w Play (`docs/TESTY.md`). Zrobione 07-08.10, wszystko **czeka na sprawdzenie** (poza zmianami w samym placu):
- **Wejście na mapę**: cała mapa wczytuje się przy wejściu do gry (koniec doładowywania), start rundy z krótkim ciemnym przejściem, żeby cienie zdążyły się zbudować; po rundzie odbudowują się tylko zniszczone budynki (mniej pracy dla serwera i graczy).
- **Grafika**: jeden profil dla wszystkich, pośrodku dawnych trybów Ziemniak/Pełny (tryby i ich wybór usunięte).
- **Destrukcja**: ~25% małego rumowiska zostaje twarde do końca rundy (prawdziwe ruiny, po których się chodzi); latarnie padają w całości jak meble; drzwi nie wiszą już w powietrzu po zawaleniu; gruz w kilku odcieniach szarego.
- **Ruch**: drabinę łatwiej złapać zwykłym chodem (dobijanie prędkości tuż przed szczeblami); zejście po drabinie nie liczy się jako upadek. Dwie bardziej rozbudowane wersje drabiny odrzucone.
- **Most**: ghost widoczny także na tle lawy (nieprzezroczysty), kąt startowy równo z ulicami (co 45°), most dłuższy o 3 studa.
- **Mapa (Studio)**: nowe lampy w budynkach i wentylatory przestawione na studsowy wygląd; drabiny oznaczone do przyciągania; drzwi widoczne dla destrukcji.

## Stan na 2026-09-30

Przegląd kodu 29.09 i naprawy w paczkach — wszystko czeka na test Kacpra w Play (`docs/TESTY.md`). Co zostało do wypuszczenia gry: `docs/DO_RELEASE.md`. Decyzje: destrukcja zostaje na prawdziwej fizyce, gruz nie rani; loadout 3 itemy na rundę; anty-cheat cofa gracza; na telefon przyciski dotykowe.
