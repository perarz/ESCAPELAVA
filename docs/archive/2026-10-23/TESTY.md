> ARCHIWUM sprzed audytu 23.10.2026. To zapis historyczny, nie bieżące instrukcje ani lista zadań. Aktualne dokumenty są dwa poziomy wyżej.

# CO PRZETESTOWAĆ

Zaznaczaj `[x]`. Jak coś nie działa — dopisz obok, co się stało.
Po testach destrukcji skopiuj Claude'owi z Output linie `[Collapse]` i `[Destr]`.
Jak coś wisi w powietrzu — **nie zatrzymuj Play**, napisz Claude'owi: przeskanuje to na żywo.

**Zanim zaczniesz:** VS Code otwarty (sam włącza Rojo), wtyczka Rojo w Studio połączona.

---

## RPG OBURĄCZ / WYCIĄGANIE (21.10) — NIEPRZETESTOWANE
- [ ] RPG: wyciąganie zza prawego ramienia trwa 0,7 s; lewa dłoń podchodzi pod lufę i zostaje tam w staniu, biegu i skoku
- [ ] Strzał od razu przerywa wyciąganie; przy zapasie rakiet obie ręce dalej trzymają RPG
- [ ] F z RPG: pełne pchnięcie, potem powrót do chwytu oburącz
- [ ] Ragdoll / drabina / siedzenie: ręce swobodne, po powrocie do zwykłego ruchu chwyt wraca
- [ ] Zmiana itemu, ostatnia rakieta i respawn: lewa ręka nie zostaje przy starej lufie; drugi gracz widzi chwyt oburącz
- [ ] Bomba, hak i blueprint: wyciąganie krótsze, 0,3 s

## 🎥 SKLEP: KĄT, ŚWIATŁO, DŁUŻSZA ŚCIANA (23.10) — NIEPRZETESTOWANE
- [ ] Każdy item widać lekko z boku (~20°) i trochę z góry, nie płasko na wprost. Inny kąt → `Config.Shop.AutoCameraYaw` (0 = na wprost, minus = z drugiej strony), z góry → `AutoCameraPitch`
- [ ] Przewiń wszystkie 6 itemów (także RPG i bombę na końcach) → w kadrze tylko półki, blat i podłoga, nigdzie szarej ściany ani sufitu
- [ ] Światło jasne, białe (nie łososiowe) — kolory itemów prawdziwe; RPG (kamera najdalej) nie jest ciemny, bomba nie jest prześwietlona
- [ ] Plac: **Cmd+S** (ściana, itemy i lampa zmienione przez MCP)

## 💡 ŚWIATŁO W SKLEPIE (21.10) — NIEPRZETESTOWANE
- [ ] **(21.10 wieczór) Nowy panel sklepu**: pasek na dole w stylu ekwipunku — pomarańczowy nagłówek z nazwą i twoją kasą (zielona) po prawej, cena, opis, paski POWER/RANGE/MOBILITY (dojeżdżają przy zmianie itemu), zielony BUY; za mało kasy → szary „NOT ENOUGH $”; po zakupie „BOUGHT!” albo „ADD IT IN INVENTORY”; strzałki < > po bokach ekranu i A/D przewijają; X zamyka; wszystko po angielsku (też podpowiedź przy sprzedawcy: „Shop”)
- [ ] **Kolejność**: sklep otwiera się na bombie (pierwszy z lewej), > idzie po ścianie w prawo: bomba → energy drink → most → hak → RPG, bez skakania tam i z powrotem
- [ ] Mały ekran / telefon: panel mniejszy razem z HUD, mieści się
- [ ] Itemy na ścianie stoją szerzej (co ~9 studów), kamera dalej — w kadrze widać item w całości z odstępem
- [ ] **(21.10) Kadry**: każdy item (bomba, most, hak, puszka, RPG) widać PROSTO z przodu, lekko z góry, nie od dołu; podobnej wielkości na ekranie; kamera nie stoi za ścianą. Za blisko/daleko → `Config.Shop.AutoCameraFill`, kąt → `AutoCameraPitch`
- [ ] Otwórz sklep i przewijaj itemy ◀▶ → każdy item tak samo dobrze oświetlony, światło płynnie jedzie razem z kamerą (bez skoków)
- [ ] Zamknij sklep i otwórz ponownie → dalej działa; w scenie sklepu nie widać szarego klocka światła
- [ ] Za ciemno / za jasno → SpotLight w `WeaponShopScene.ShopLight` (Brightness, Range, Angle)

## 🛢️ BECZKI WYBUCHOWE (21.10) — NIEPRZETESTOWANE
Beczki: 9 na budowie (Construction), 4 przy ulicy.
- [ ] Bomba albo RPG tuż przy beczce → beczka wybucha od razu, rozlatuje się, chwilę płonie; wybuch WIĘKSZY niż bomba (większa dziura, dalej rzuca graczy)
- [ ] Beczki stojące obok siebie → wybuchają łańcuchowo
- [ ] F (pchnięcie) w beczkę przed sobą → od razu wybucha (pchający też obrywa, jeśli nie ucieknie)
- [ ] F, gdy gracz stoi bliżej niż beczka → zwykłe pchnięcie gracza, beczka zostaje
- [ ] Drugi gracz zginie od wybuchu beczki → „YOU KILLED” i 25$ dla tego, kto ją odpalił (bombą, RPG albo F)
- [ ] Pełne HP w samym środku wybuchu beczki → przeżywa z małą ilością HP (78% obrażeń)
- [ ] Następna runda → wszystkie beczki stoją z powrotem
- [ ] **(21.10) Zawalenie**: zawal budowę (Construction) pod beczkami (piętro ~45 i parter) → beczki SPADAJĄ w całości i wybuchają przy uderzeniu o ziemię/gruz (nie znikają, nie wiszą). Za szybko/za późno → `Config.Destruction.Cars.Fall`
- [ ] Beczka spadnie i się zaklinuje → wybucha najpóźniej po ~6 s
- [ ] Za mocno / za słabo → liczby w `Config.Destruction.Cars.Profiles.Barrels`

## ⚡ ENERGY DRINK (20.10 wieczór) — NIEPRZETESTOWANE
- [ ] **21.10 — poprawka picia:** na stojąco i w biegu wieczko podchodzi przed usta, puszka lekko się przechyla i ręka opada; nie przykłada puszki do prawego ucha. Sprawdzić też przy obrocie kamery.
**Najpierw:** Rojo w Studio połączone (Connect) i plac zapisany (Cmd+S) — puszka do ręki to nowy model w `ReplicatedStorage`.
- [ ] Sklep: jest „Energy Drink” za 25$, z ikoną puszki z błyskawicą; kupno działa
- [ ] Ekwipunek: karta fioletowa z ikoną, w DETAILS kręci się puszka; da się włożyć do loadoutu (zamiast innego itemu — sloty są 3)
- [ ] Wyciągnięcie w rundzie: puszka w dłoni stoi PIONOWO, wieczkiem do góry. Jeśli leży albo stoi do góry dnem → napisz, poprawię jedną liczbę (`Config.EnergyDrink.GripRotation`)
- [ ] Biegniesz z shiftem i klikasz → ręka podnosi puszkę do ust (~pół sekundy), bieg się NIE zatrzymuje
- [ ] **(21.10)** Po łyku przez 10 s: sprint bez końca; zwykły chód wyraźnie szybszy (+3), sprint bez zmian; kamera trochę szersza (+5 FOV); pasek staminy: obrys wyraźnie GRUBSZY, obrys i środek płynnie przechodzą przez różne odcienie ZŁOTA (każdy w innym momencie), w ostatnich 2 s szybciej; na KRAWĘDZIACH ekranu winieta jak czerwona przy obrażeniach, tylko złota, pulsuje (środek ekranu czysty; wchodzi i schodzi płynnie); widać pasek też, gdy stoisz; potem wszystko wraca do normy, także po śmierci
- [ ] Pijesz z pustą staminą (wyczerpany, sprint zablokowany) i trzymasz shift → od razu biegniesz dalej
- [ ] Drugi napój w trakcie działania → czas liczy się od nowa do 10 s (nie sumuje się)
- [ ] Ostatnia puszka: znika z ręki po łyku; z kilkoma sztukami puszka zostaje w ręce
- [ ] Drugi gracz (jeśli jest): widzi, jak pijesz (ręka do ust)
- [ ] Śmierć albo koniec rundy w trakcie działania → w lobby pasek normalny, bez kolorów
- [ ] Ruch ręki przy łyku wygląda głupio (za nisko / za wysoko / ręka w głowie) → opisz, stroję liczby w `Config.EnergyDrink.Sip`

## 🚀 RPG — ETAP 1 (20.10 wieczór) — NIEPRZETESTOWANE
Strzał, wybuch, odrzut (21.10). Rocket jump zrobiony i usunięty 21.10 (Kacper: „po prostu jak bomba”). Zostaje dźwięk strzału.
- [ ] Sklep: „RPG” za 75$ z ikoną; ekwipunek: karta oliwkowa, w DETAILS kręci się wyrzutnia
- [ ] Wyciągnięcie: wyrzutnia w dłoni trzymana POZIOMO, głowicą do przodu, ręka na rękojeści pod lufą. Jeśli jest krzywo / tyłem → zrzut ekranu
- [ ] Klik → rakieta (zielona głowica) leci prosto tam, gdzie celujesz, szybko, z białą smugą, bez opadania
- [ ] Trafia ścianę / dach / ulicę → wybuch jak bomba, ale wyraźnie mniejsza dziura i mniejszy zasięg
- [ ] Trafia drugiego gracza → wybuch na nim, rani i odrzuca; zabójstwo = „YOU KILLED” i 25$
- [ ] **(21.10, rocket jump usunięty)** Strzał pod własne nogi → rani i wywraca jak każdego, bez wyrzutu w górę
- [ ] **(21.10) Wybuchy ranią KAŻDEGO, też odpalającego** — także na prawdziwym serwerze: własna bomba, RPG, beczka, auto. Śmierć od własnego wybuchu = bez nagrody; jeśli ktoś cię wcześniej trafił, zabójstwo zostaje dla niego
- [ ] Strzał w lawę → wybucha na tafli lawy, nie pod nią
- [ ] Strzał w niebo → rakieta znika daleko z wybuchem w powietrzu (~300 studów)
- [ ] 1 rakieta = 1 strzał: po strzale wyrzutnia znika z ręki (przy kilku sztukach zostaje)
- [ ] Koniec rundy (O) z rakietą w locie → nic nie wybucha na odbudowanej mapie
- [ ] W Output przy strzale `[Rpg] … strzał`, bez czerwonych błędów
- [ ] **(21.10) Odrzut, „mocno”**: u strzelca kamera NIE zmienia kierunku (celujesz dalej w to samo miejsce) — tylko krótko się trzęsie i oddala (zoom-out) i wraca; z przodu wyrzutni błysk ognia i dym, z tyłu kłąb dymu (backblast); ręka z wyrzutnią kopie do góry/do tyłu i wraca (~0,5 s)
- [ ] Drugi gracz widzi błysk, dym i kop ręki strzelca (kamera trzęsie się tylko u strzelca)
- [ ] Ostatnia rakieta (wyrzutnia znika z ręki) → błysk i dym dalej w dobrym miejscu, przy ramieniu
- [ ] Za mocno / za słabo / dym w złym miejscu → liczby w `Config.Rpg.Recoil`

## 🖥️ EKRAN ŁADOWANIA v2 + NAPIS SHOP WYŻEJ (20.10 wieczór) — NIEPRZETESTOWANE
- [ ] Wejście do gry: mały szary „LOADING...”, pod nim duże żółte „ESCAPE LAVA” (LAVA pomarańczowe), nowa czcionka (prostsza); pasek ciemnopomarańczowy ze studsami w wypełnieniu, puste tło paska bez studsów
- [ ] Na końcu wszystko płynnie znika (studsy też)
- [ ] Lobby: napis SHOP wyraźnie wyżej nad sprzedawcą niż wcześniej

## 🏆 „YOU SURVIVED!” + KASA (20.10) — NIEPRZETESTOWANE
- [ ] Przeżyj rundę (klawisz O = koniec rundy) → na środku, w miejscu komunikatu zabójstwa, wskakuje złote „YOU SURVIVED!”, pod nim zielone „+100$”; po ~2,5 s gaśnie, zanim ekran ściemnieje do lobby. Starego żółtego „NICK WON $100” nie ma
- [ ] Zgiń w rundzie (lawa) i poczekaj do końca → NIC się nie pokazuje (komunikat tylko dla ocalałych)
- [ ] Ekran telefonu / małe okno Studio → napis mniejszy razem z resztą HUD, nie wychodzi poza ekran
- [ ] Zabij kogoś tuż przed końcem rundy → „YOU KILLED” znika, gdy wskakuje „YOU SURVIVED!” (nie nakładają się)
- [ ] Licznik kasy w lewym dolnym rogu: żywszy gradient — jasna limonka u góry, ciemna zieleń na dole (jak banknoty w ikonie); połysk przy zbieraniu kasy dalej przejeżdża

## 🛒 NAPIS SHOP (19.10) — NIEPRZETESTOWANE
- [ ] Wysoko nad straganem wisi „SHOP” w kolorach lawy, kolory płyną przez napis w kółko (bez przeskoku); widać go przez ściany straganu; z mapy w trakcie rundy go nie widać; po śmierci w lobby znowu widać

## 🎒 EKWIPUNEK / LOADOUT (18.10) — NIEPRZETESTOWANE
- [ ] **(19.10) Lawa w panelach ma jedną warstwę** (płynie w jedną stronę)
- [ ] **(19.10) Dwa okna**: `I` → na środku samo okno INVENTORY + LOADOUT. Klik w item → okno odjeżdża w lewo, z prawej wysuwa się DETAILS (z nazwą, kręcącym się itemem, opisem, cechami), para stoi razem na środku. Klik w inny item = podmiana treści; ten sam item drugi raz albo mały X = DETAILS chowa się, okno wraca na środek
- [ ] DETAILS → **ADD TO LOADOUT** (zielony) wkłada item do wolnego slotu (ikona przelatuje); przy itemie z loadoutu przycisk to **REMOVE** (czerwony); przy pełnym loadoucie **SWAP INTO SLOT** (żółty) → sloty się trzęsą, napis „PICK A SLOT TO SWAP”, klik w slot = podmiana
- [ ] Klik w slot z itemem = pokazuje go w DETAILS; klik w pusty slot przy otwartym DETAILS = wkłada tam pokazany item
- [ ] **(19.10) Nowe ikony** (render z gry + czarny obrys) w pasku i w ekwipunku: bomba, most, hak czytelne
- [ ] **(19.10) Animacje**: po otwarciu karty i sloty wskakują po kolei; karta pod kursorem rośnie i lekko się przechyla; nazwa i licznik w DETAILS podskakują przy zmianie itemu; nowy numer slotu na karcie podskakuje; przy zamknięciu panel opada. Przycisk INVENTORY większy, bez „I”
- [ ] **(19.10, poprawka) Item w DETAILS mieści się w okienku** (nie wystaje nad ramkę, jest na środku); przeciągnięty klocek upuszczony na slot trafia w ten slot; lecąca ikona startuje z karty, nie wyżej. **Lobby trwa 25 s** (było 15)
- [ ] **(19.10) DETAILS = prawdziwy item**: w okienku DETAILS kręci się item z prawdziwym światłem (odblaski, cień), na ciemnym tle; zmienia się przy najechaniu na inny item; nie przesuwa się względem okna, gdy kamera się rusza (bieg, obrót); nic ze świata nie wchodzi w okno; po zamknięciu panelu znika. Telefon: to samo
- [ ] **(19.10) Wygląd klasyczny**: czarny obrys na wszystkim, pomarańczowy nagłówek, karty itemów w kolorach (x0 szara z zieloną ceną), sloty loadoutu wyglądają jak pasek na dole i stoją na płynącej lawie; karta rośnie pod kursorem, ikona wpada do slotu z odbiciem; model w DETAILS się kręci
- [ ] `I` albo przycisk INVENTORY (lewa strona) → panel spada na miejsce, tło ciemnieje; `I` / X zamyka. **(20.10) Klik w ciemne tło NIE zamyka** (i nie rzuca bomby / nie strzela hakiem pod spodem); klik w puste miejsce panelu też nie
- [ ] Najechanie na item → DETAILS: model 3D się kręci, opis, paski POWER / RANGE / MOBILITY dojeżdżają
- [ ] Klik itemu → ikona przelatuje do slotu; klik itemu z zielonym numerkiem → wyjmuje go ze slotu
- [ ] **(19.10) Przeciąganie**: jedzie CAŁA karta / cały slot (lekko większa, przechyla się w stronę ruchu), miejsce po niej się kurczy. Upuszczona na slot — wskakuje do niego sprężyście, slot podskakuje. Upuszczona obok — wraca sprężyście na miejsce. Slot upuszczony obok slotów — kurczy się z obrotem i znika (wyjęty). Slot na slot = zamiana; prawy klik slotu = wyjęcie
- [ ] Najedź na item i wciśnij 2 → item w slocie 2, a pasek NIE wyciąga itemu
- [ ] Pasek na dole = sloty loadoutu, nic się nie przestawia, gdy skończą się bomby (slot „x0”, szary, w lobby pulsuje na czerwono; klik = potrząśnięcie)
- [ ] **(19.10) Ekwipunek tylko w lobby**: po starcie rundy przycisk INVENTORY znika, klawisz I nic nie robi, otwarty panel sam się zamyka; w lobby wszystko wraca
- [ ] Wyjmij hak z loadoutu → klawisz 3 / slot nie wyciąga haka (serwer też nie da)
- [ ] Pełny loadout + kup item spoza niego → sklep: „ADD IT IN INVENTORY”, na przycisku INVENTORY czerwone „!”
- [ ] Ustaw loadout, wyjdź, wejdź → ten sam układ
- [ ] Telefon: tap itemu = DETAILS, drugi tap = do slotu; przeciąganie palcem działa

---

## 🖥️ EKRAN ŁADOWANIA (20.10) — NIEPRZETESTOWANE
- [ ] Wejście do gry: od razu czarne tło, napis ESCAPE LAVA i pasek pod nim (nie ma szarego ekranu Robloxa ani starego z małym pomarańczowym paskiem)
- [ ] Pasek rośnie płynnie (bez skoków w tył), procent liczy razem z nim, napisy po angielsku: CONNECTING → LOADING ASSETS → LOADING MAP → LOADING PLAYER → LIGHTING UP → READY!
- [ ] Na końcu pasek dobiega do 100% i cały ekran płynnie znika (z czarnymi obrysami — nie zostają same ramki na chwilę)
- [ ] Telefon / małe okno: napis i pasek mieszczą się, nic nie wystaje
- [ ] W Output **NIE MA** `[LoadingScreen] brak ReplicatedFirst.LoadingGui` — jeśli jest, plac nie był zapisany po zmianie (Cmd+S)

## 📱 START GRY NA WOLNYM TELEFONIE (paczka 3, 18.10) — NIEPRZETESTOWANE
- [ ] Wejdź do gry → ekran ładowania pokazuje „LOADING PLAYER...”, a po zejściu kasa, pasek itemów i czas są już prawidłowe (nie „0$”, nie pusty pasek)
- [ ] Wejdź w **trakcie rundy** → HUD od razu pokazuje ROUND i czas, nie „LOBBY”
- [ ] Kup coś, wyjdź, wejdź → kasa i itemy widać od razu po zejściu ekranu ładowania
- [ ] Studio: Network → wolna sieć (throttling), wejdź → to samo co wyżej
- [ ] Sklep: otwórz → kwota i „za mało kasy” się zgadzają
- [ ] Ruch, sprint, kamera, hak, most, bomba, pchnięcie, drabina działają jak wcześniej (kontrolery startują teraz równolegle)
- [ ] W Output **NIE MA**: `bez ClientReady`, `init padł`, `stan gracza … nie doszedł`. Jeśli są — wklej je Claude'owi

---

## 🎨 NOWE UI Z FIGMY (10.10)
- [ ] **(18.10) Pasek itemów**: wybrany slot NIE nachodzi na sąsiada (też w chwili wyciągnięcia); zmiana 1 → 2 → 3 płynna — stary slot opada razem z wjazdem nowego, ikona buja się lekko, bez szarpnięcia. Rzut bombą: slot nie podskakuje przy każdym rzucie
- [ ] Licznik kasy w lewym dolnym rogu: banknoty + zielona liczba z czarnym cieniem; zmienia się przy zbieraniu/wydawaniu
- [ ] Zbierz kasę z mapy → banknot wyskakuje na środku ekranu i leci do licznika, licznik podskakuje, liczba płynnie rośnie
- [ ] Zabójstwo (25$) → 3 banknoty, wygrana (100$) → 6, jeden po drugim
- [ ] Zakup w sklepie → liczba spada od razu, bez banknotów; zakup w trakcie lotu banknotów nie psuje licznika
- [ ] Wejście do gry → licznik od razu pokazuje stan, bez lecących banknotów
- [ ] Pasek: 3 sloty z IKONAMI (bomba, most, hak), mała angielska nazwa na dole, numer klawisza w lewym górnym rogu (bez kółka), liczba sztuk w prawym; wybrany → biała ramka
- [x] Pasek, ramka (poprawka 10.10): wybierz item → biała ramka; kliknij ten sam slot / klawisz drugi raz (schowaj) → ramka wraca do czarnej. Powtórz kilka razy na każdym slocie i po rzucie bombą — biała nie może zostać na schowanym slocie
- [ ] Czas na górze (Figma, 10.10): napis stanu biały z cieniem, po bokach czarne kreski zwężające się na zewnątrz; czas pod spodem żółto-pomarańczowy. Przejdź LOBBY → GET READY → ROUND → ROUND OVER — kreski zawsze tuż przy napisie, nic nie nachodzi; sprawdź mały i duży ekran (telefon)
- [ ] Licznik czasu przy samej górze ekranu (10.10 wieczór): w oknie Studio, na pełnym ekranie i na telefonie (emulator) zawsze ~4 px od górnej krawędzi, nic go nie zasłania; reszta HUD na miejscu (kasa, pasek, przyciski z boku)
- [ ] Kamera w ruchu (11.10): chodzenie → kamera spokojna (zero bujania); sprint po ziemi → lekkie, płynne drżenie, znika po puszczeniu shifta i w powietrzu; bieg w bok (A/D) → kamera lekko się przechyla w stronę ruchu i wraca; F (push) → krótkie szarpnięcie + mały zoom u popychającego, także przy pudle; nic z tego w ragdollu; kamera dalej nie wchodzi w ściany. Za mocne / za słabe → `Config.Movement.Camera.SprintShake.Amplitude`, `.Lean.MaxDegrees` (1,2° od 11.10), `Config.Push.PushShakeIntensity`
- [ ] Bez GET READY (11.10): lobby odlicza do 0, ekran ściemnia się w ostatniej chwili i od razu startuje runda na mapie (bez 5 s „GET READY”); po rundzie lobby → budynki znowu stoją i walą się normalnie (przebudowa przeniesiona na wejście do lobby); ktoś wychodzi w lobby przy MinPlayers 2 → ekran nie zostaje czarny
- [ ] Przełączanie itemów (11.10): hak → bomba → most → hak w różnej kolejności, także szybko — w ręce zawsze JEDEN przedmiot, w pasku podniesiony tylko jeden slot
- [ ] Runda bez faz (11.10): lawa przez pierwsze ~15 s prawie stoi, potem przyspiesza płynnie bez skoków; po 240 s jest ~120 studów wyżej (zalewa najwyższy dach); w logu serwera brak linii `[GameLoop] phase`; klawisz skip w rundzie kończy rundę
- [ ] Wyciąganie itemu (11.10): klik / klawisz → slot podskakuje, zostaje wyżej i trochę większy, ikona się buja; schowanie → opada; rzut bombą (auto-wyciągnięcie następnej) → slot NIE skacze przy każdym rzucie; zmiana itemu 1 → 2 → slot 1 opada, 2 wjeżdża
- [ ] Licznik czasu (11.10): przy zmianie LOBBY → GET READY → ROUND → ROUND OVER napis wskakuje; ostatnie 10 s lobby / odliczania / rundy → czas czerwony i podskakuje co sekundę, potem wraca do żółtego
- [ ] Zakup w sklepie (11.10): liczba kasy spada płynnie (nie skokiem), licznik krótko się chwieje
- [ ] Pasek staminy (11.10): pobiegnij w małym oknie Studio, na pełnym ekranie i w emulatorze telefonu, z kamerą blisko i daleko — obrys i odstęp wypełnienia od ramki zawsze w tych samych proporcjach (nie cienka nitka na dużym ekranie, nie gruby klocek na telefonie)
- [ ] Balans (10.10 wieczór): push co 2,5 s (pasek odnowienia krótszy niż wcześniej 4 s); bomba w epicentrum zabiera 60% HP (było 50%) — dwie bomby blisko nadal nie muszą zabić, sprawdzić odczucie; lawa buja się mniej (fala o połowę niższa)
- [ ] Zbieranie kasy (11.10): na środku ekranu za banknotami zielony błysk, promienie, dwa pierścienie i migoczące gwiazdki — BEZ iskierek; nic nie zostaje na ekranie po ~1 s; napis kasy: pionowy gradient (góra jaśniejsza), przy dolocie banknotu przejeżdża po nim jasny połysk
- [ ] Kasa (10.10 wieczór): w spoczynku napis równo zielony, bez ruchu; przy zebraniu kasy przez napis raz przejeżdża jasny połysk (przy kilku banknotach naraz — bez szarpania)
- [ ] Licznik czasu: bez poświat, kreski ostre (nie rozmyte) w oknie i na pełnym ekranie
- [ ] Komunikat zabójstwa (Figma, 10.10, potrzebny drugi gracz): zabij kogoś (bomba / zepchnięcie do lawy) → na środku nad połową ekranu wskakuje „YOU KILLED <nick>” z czerwonym KILLED i czaszkami, pod spodem „+25$”; po ~2,5 s gaśnie. Zabity NIE widzi komunikatu, killfeedu w prawym górnym rogu już nie ma. Dwa zabójstwa szybko po sobie → drugi nick, komunikat od nowa, nie znika w połowie. Długi nick nie nachodzi na czaszki
- [ ] Dolot banknotu: z ikony wybuchają zielone iskierki, za ikoną błyska zielona poświata
- [ ] Licznik kasy: inny odcień zieleni, połysk przesuwa się po napisie w kółko; ikona przechyla się przy dolocie banknotu
- [ ] Sklep pokazuje angielskie nazwy (Bomb / Bridge / Grapple)
- [ ] Małe okno / telefon: wszystko się zmniejsza proporcjonalnie, nic nie wychodzi za ekran

## 🆕 NAJPIERW — ZMIANY Z 30.09-08.10

> **10.10:** potwierdzone ✅ gęsta lawa, mosty + ghost, jeden profil grafiki, drabiny. Eksplozje „raczej git, nie na 100%” — zostają do stałego testu T1-T7 niżej.

### 🌋 Gęsta lawa — ✅ Kacper 10.10: „gęsta lawa git”
- [x] Skok z dachu do głębokiej lawy → nie lecisz na dno, tylko wpadasz kilka studów i powoli opadasz
- [x] W lawie ruszasz się wyraźnie wolniej (jak w miodzie)
- [x] Trzymasz skok → powoli płyniesz w górę
- [x] Przy powierzchni trzymany skok wybija z lawy
- [x] Da się dopłynąć do brzegu (dach, gruz) i wyjść
- [x] Kamera pod powierzchnią → ekran pomarańczowy i rozmyty, nie widać ulicy na dnie
- [x] Opadniesz na dno pod lawą → **zero** obrażeń od upadku i brak wywrotki w locie
- [x] W lawie dalej boli (~7 s do śmierci z pełnym życiem)

### 🌉 Mosty — ✅ Kacper 10.10: „mosty git”
- [x] Celujesz w lawę → podgląd czerwony, klik nic nie robi, most nie znika z ekwipunku
- [x] Most między dwoma dachami leży i da się po nim przejść
- [x] Most wysunięty nad przepaść przechyla się i spada
- [x] Most postawiony na dachu przez murek/gzyms NIE wylatuje w powietrze
- [x] Bomba odrzuca cały most w jednym kawałku (nie rozpada się na deski)

### 🎨 Jeden profil grafiki (08.10) — ✅ Kacper 10.10: „jeden profil grafiki działa” (telefon niesprawdzony)
- [x] Gra startuje bez błędów (nie ma już trybów Ziemniak/Pełny ani klawisza G)
- [x] Wybuch: gruz i cząsteczki „pośrodku” — więcej niż dawny Ziemniak, mniej niż Pełny; meble się rozsypują; gruz leży ~10 s
- [ ] Na telefonie (jeśli możesz) kilka bomb naraz nie zacina

### 🧱 Twarde ruiny (08.10)
- [ ] Zawal kawałek budynku → część (~1/4) małych brył i fragmentów zostaje do końca rundy, twarda, w swoim kształcie — da się na nich stanąć
- [ ] Reszta dalej znika / jest gruzem bez kolizji; serwer nie laguje bardziej niż wcześniej
- [ ] Wklej z Output linie `[Collapse] … twarda ruina` i `kruszenie … małych twardych N`

### 💡 Latarnie i sygnalizatory (08.10)
- [ ] Bomba tuż przy latarni / sygnalizatorze → rozpada się na kawałki, nic nie wisi
- [ ] Bomba kilka studów dalej → przewraca się w całości (nie zostaje pół słupa ani sama głowica w powietrzu)

### ⏱️ Wyjście z Play w Studio (08.10, poprawione 19.10) — NIEPRZETESTOWANE
- ❌ 19.10: poprawka z 08.10 nie działała — każde wyjście trwało ~27 s (log Studio)
- [ ] **(19.10)** Stop → Studio odwiesza się w ~1-2 s; w Output `BindToClose done po X s` z X poniżej 2
- [ ] Kup coś, Stop, Play → kasa i itemy zostały (zapis dalej działa)
- [ ] Jeśli dalej wisi: wklej linię `BindToClose: limit … minął — …` (mówi, co trzyma)

### 🚪 Drzwi (08.10)
- [ ] Zawal ścianę/strop przy drzwiach w PupleHotel i SandBuilding → drzwi spadają, nie wiszą
- [ ] Przez drzwi dalej da się przejść

### 🌉 Ghost mostu (08.10) — ✅ Kacper 10.10: „mosty git”
- [x] Celuj mostem w lawę (lawa w tle) → ghost WIDAĆ (pełny, zielony/czerwony, bez prześwitu)
- [x] Wejdź w budowanie, patrząc ukosem na ulicę → most stoi równo z ulicą (kąt co 45°), R obraca co 45°
- [x] Postawiony most stoi dokładnie tam i tak, jak pokazywał ghost

### 🪜 Drabiny (08.10, v3 — tylko łatwiejsze łapanie, reszta jak w zwykłym Robloxie) — ✅ Kacper 10.10: „drabiny sprawdzone”
- [x] Zwykły chód (bez sprintu) prosto na drabinę → łapie
- [x] Podejście lekko ukosem → łapie
- [x] Na górze wyjdź na dach → NIE pcha z powrotem na krawędź
- [x] Zejście po drabinie z góry na ziemię → zero obrażeń od upadku

### 🌆 Ładowanie mapy i przejście (07.10)
- [ ] Wejście do gry: ekran ładowania może trwać dłużej (cała mapa) — ile sekund? Na telefonie też
- [ ] Koniec odliczania: ekran płynnie ciemnieje, po ~1-2 s rozjaśnia się NA MAPIE, z cieniami i oświetleniem od razu (bez doskakiwania 10-20 s). Jeśli cienie dalej dochodzą → podnieść `Config.RoundTransition.SettleTime`
- [ ] Odliczanie przerwane (za mało graczy) → ekran nie zostaje ciemny
- [ ] Druga i trzecia runda: zburzony budynek wraca cały, nietknięte stoją; w Output linia `[Map] restored X/32 jednostek (...)` — X ≈ tyle, ile ruszyłeś (wkleić ją)
- [ ] Przyciemniony (ranny, nie przecięty) element wraca do normalnego koloru w następnej rundzie

### 💥 Destrukcja — poprawki
- [x] **Kebab**: końcówki filarków i narożny słupek nie wiszą, dach nie stoi na kawałku ściany (Kacper 01.10: „kebab git”)
- [ ] **Zielony**: zwal cały GreenBuilding → skrzynie, paczki i palety z górnych pięter NIE zostają w powietrzu
- [ ] **Kebab — dach**: czy dach potrafi jeszcze stać na jednym kawałku ściany w rogu (sprawdzić przy okazji)
- [ ] **Kolor gruzu (07.10)**: kawałki po wybuchu mają RÓŻNE odcienie szarego (od grafitu do jasnego popiołu), a nie jeden; dalej wyraźnie odróżniają się od mapy

---

## 💥 DESTRUKCJA — STAŁY TEST

Zawsze ta sama kolejność. 2 razy bez błędu pod rząd = destrukcja skończona.

- [ ] **T1** OrangeBuilding, parter — bomby w (−385, −145), potem (−365, −143), potem (−384, −121)
  → budynek kładzie się piętrami, nic nie wisi w powietrzu
- [ ] **T2** OrangeBuilding — bomba na piętrze Y 54, potem cała seria T1
  → gruz z góry spada razem z piętrem niżej
- [ ] **T3** Stań na piętrze Y 54, ktoś robi T1
  → jedziesz z piętrem, gruz NIE rani, na dole zwykły upadek
- [ ] **T4** GreenBuilding, parter koło (−250, −161) — 3 bomby co sekundę
  → wieżowiec składa się piętrami
- [ ] **T5** W trakcie T4 rzuć bombę w spadające piętro
  → tylko lekko je popycha
- [ ] **T6** Po T4 bomba w leżący gruz
  → robi dziurę, gruz lekko drga, nie wystrzeliwuje
- [ ] **T7** SandBuilding, parter koło (−157, 133) — 5 bomb w 3 sekundy
  → bez lagów
- [ ] Kurz przy zawalaniu wygląda dobrze (nie za mało)

**Nie może się stać:** blok wiszący w powietrzu dłużej niż sekundę · znikające piętro · śmierć od gruzu · wystrzelony blok.

## 💥 DESTRUKCJA — RESZTA

Budynki, które jeszcze nigdy nie były grane na nowej destrukcji:
- [ ] PurpleSchool
- [ ] OldBuilding1
- [ ] Construction
- [ ] PupleHotel
- [ ] SandBuilding (poza T7)
- [ ] OldBuilding2

Reszta:
- [x] Tory w budynku spadają z nim, reszta torów zostaje ✅ 01.10
- [ ] Wieszaki i drobne rzeczy przy bombie znikają w chmurze pyłu
- [ ] Meble dalej od bomby odlatują w całości, druga bomba je rozwala
- [ ] TV na szafce i deski rusztowania nie wiszą w powietrzu
- [ ] Auto przy bombie wybucha i płonie
- [ ] Auta tuż obok wybuchają po kolei
- [ ] Gruz leży płasko, nie sterczy

## 🧍 GRACZ I ZAPIS

- [ ] Wyjdź i wejdź → **ta sama postać** (w Studio pierwsze wejście od zera — nowy zapis)
- [ ] Kasa i itemy zostają po wyjściu
- [ ] 2 graczy w Studio, drugi wchodzi w trakcie odliczania → ląduje w lobby jako widz, runda się normalnie kończy
- [ ] Stop Play → w Output: `BindToClose done (zapisów w toku: 0)`

## 🛒 SKLEP I HOTBAR

- [ ] Szybkie klikanie KUP → każdy zakup przechodzi
- [ ] ▶ w sklepie i od razu Q → kamera bez szarpnięcia
- [ ] Trzymasz bombę, giniesz albo kończy się runda → jeden klik znowu ją daje
- [ ] Masz 1 bombę i most, rzucasz bombę → zaznaczenie nie skacze samo na most
- [ ] Rzucasz bomby tak szybko, jak pozwala pasek → każdy rzut wychodzi

## 🏃 RUCH

- [x] Pasek staminy jest dalej po śmierci ✅ 01.10
- [x] Przewrócony bombą (ragdoll) z Shiftem → stamina się nie zużywa ✅ 01.10
- [x] W ragdollu głowa nie wykręca się ✅ 01.10
- [x] Hak w ragdollu nie strzela ✅ 01.10
- [x] Ekran ładowania przy wejściu znika normalnie ✅ 01.10

## 📜 STARE ZALEGŁE

- [x] Obrażenia od upadku — 5 przypadków z 19.09 ✅ 01.10
  *dla Claude'a:* lista przy `FallDamageService` w `docs/ARCHITECTURE.md`


## 11.10 — kierunkowy chód/sprint R15 (DO TESTU KACPRA)

8 kierunków chodu; sprint tylko W, W+A, W+D; postać patrzy zgodnie z kamerą. Sprawdzić zmianę kierunku i tempa, start/stop pod ścianą, zatrzymanie zużycia staminy podczas Shift+A/D/S, skoki, drabiny, lawę, hak, ragdoll, śmierć/respawn i sklep. Potem wyłączyć `Config.DirectionalLocomotion.Enabled`, ponowić Play: stare animacje i obracanie oraz sprint we wszystkich kierunkach. Nowe animacje to lokalny podgląd Studio, publikacja 11 assetów jeszcze nieukończona. Pełna instrukcja i rollback w `artifacts/animations/directional/README.md`. Sprawdzone bez Play: kompilacja, zgodność kodu ze Studio, 15 stawów, skończone liczby i identyczne końce 11 pętli.


### Kierunkowy ruch R15 — poprawka 11.10, wersja 2

Zestaw rozszerzony z 11 do 14 sekwencji o `Jump`, `Fall`, `Land` w `ReplicatedStorage.DirectionalAnimations` i `Config.DirectionalLocomotion.AnimationIds`. Jump/Land nie są zapętlone. Controller wybiera ruch powietrzny po stanie Humanoida i znaku prędkości Y; lądowanie nie blokuje fizyki ani wejścia. Krok przebudowany na tor stopy z oddzielnym podparciem i uniesieniem. Sprint nadal F/FR/FL, chód 8 kierunków, prędkości 12/20. Backup v1: `ServerStorage.DirectionalAnimations_v1_20261011` i `artifacts/animations/directional/backup_v1/`. Pełne cofnięcie flagą Enabled=false. Nadal StudioPreview (ID=0). Sprawdzono kompilację Edit, zgodność kodu i pętle; Play wyłącznie Kacper: ocenić unoszenie stóp, skok z miejsca/w biegu, spadanie z krawędzi, lądowanie, ragdoll, respawn.


### Kierunkowy ruch R15 — wersja 3, idle (11.10)

`ReplicatedStorage.DirectionalAnimations.Idle` i `Config.DirectionalLocomotion.AnimationIds.Idle`: 4 s, pętla, priorytet Idle. Istniejący kontroler wybiera ją na ziemi przy braku kroku, po zakończeniu lądowania; przejście `IdleBlendTime=0.20`. Faza idle nie przechodzi do chodu. W zestawie 15 klipów; Jump/Fall/Land bez zmian. Ramiona lekko odwiedzione i poruszane bocznie, tułów reaguje na kierunek. Kopia v2: `ServerStorage.DirectionalAnimations_v2_20261011` oraz `artifacts/animations/directional/backup_v2/`. Nadal StudioPreview i cofnięcie Enabled=false. Kacper sprawdza w nowym Play idle, start/stop, trzymanie przedmiotu, ruch boczny i przejście po skoku; agent sprawdził tylko dane, Blender, budowę i kompilację Edit.


Doprecyzowanie v3: Kacper wybrał swobodny idle i wyraźniejszy ruch tułowia. Wgrano mocniejszy przeciwskręt barków/bioder oraz przechył kierunkowy do 11 klipów Walk/Sprint. Idle/Jump/Fall/Land identyczne z wcześniejszą v3. Subtelny wariant zachowany w `backup_v3_subtle/` i `ServerStorage.DirectionalAnimations_v3_subtle_20261011`. Pętle i eksport sprawdzone; ocena ruchu w nowym Play po stronie Kacpra.


### Wycofanie kierunkowych animacji — 11.10

Na prośbę Kacpra usunięto DirectionalLocomotionController, jego zależność/init/bramkę sprintu w MovementController oraz Config.DirectionalLocomotion. Oryginalny Animate w StarterCharacter jest włączony i nie był zmieniany. Poprzednie sekcje o customowym chodzie/idle/skoku są historyczne. Klipy przeniesione z ReplicatedStorage do ServerStorage.DirectionalAnimations_Retired_20261011. Aktywny kierunek: default animacje + wyłącznie custom push pod F.


### Default + custom push R15 — 11.10

Aktywne: oryginalny Animate + `ReplicatedStorage.PushAnimations.Push_TwoHands_R15` (Action, 0.7 s, kontakt0.15, tylko 8 stawów górnej części ciała). `PushController` odtwarza na F, czyści track na respawn i przerywa przy śmierci/ragdollu/końcu rundy. `PushService` rezerwuje cooldown2.5 na próbę, po `Config.Push.Windup=0.15` ponownie sprawdza postać/rundę/zdrowie/ragdoll i wybiera cel. Remote Push bez payloadu; Pushed bez zmian. Koniec rundy unieważnia oczekujące próby. Config.Push.AnimationId=0, AnimationStudioPreview=true — lokalny podgląd, publikacja assetu nadal wymagana. Cofnięcie gestu AnimationEnabled=false, opóźnienia Windup=0. Szczegóły i lista prób Kacpra: `artifacts/animations/push_r15/README.md`. Kompilacja/synchronizacja i czysta logika sprawdzone, Play nieuruchamiany.

## Round transition / 3-2-1 — 18.10.2026 (do sprawdzenia przez Kacpra)

- Start: teleport pod czernią → mapa → wielkie 3,2,1 Fredoka/studs; ruch, F, bomba, hak i most dopiero po 1; lawa też startuje wtedy.
- Ostatnia śmierć: 3s bez znikania lawy/mapy; powrót martwego do lobby jak wcześniej; reset pod zasłoną.
- Wygrana po czasie: nagroda raz, przed resetem; zasłona schodzi w lobby.
- Dwie osoby: wspólne odliczanie i brak przewagi przy pierwszym spawnie.
- Dołączenie podczas odliczania: pozostała liczba, nie nowa pełna trójka; nowy gracz jest widzem do kolejnej rundy.
- Dev K z lobby: nadal pełne 3,2,1; K podczas countdown nie kończy następnej rundy.
- Telefon i szeroki ekran: cyfry mieszczą się w ekranie; następna runda i respawn nie dublują UI.
