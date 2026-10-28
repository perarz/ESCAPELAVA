# PROMPTY NA AKCESORIA — ESCAPE LAVA

> **Status 23.10.2026:** briefy modeli kosmetycznych, nie potwierdzenie gotowości sklepu/ekwipunku akcesoriów ani obowiązkowy zakres release’u. Wymiary poniżej są pomiarem z 28.09; przy zmianie rigu ponowić pomiar. Bieżący stan: [STATUS](STATUS.md), decyzje: [ROADMAP](ROADMAP.md).

> Gotowe prompty do wklejenia asystentowi, który robi modele. **Jeden model = BLOK STYLU + jeden BLOK ITEMU.**
> Wymiary postaci są ZMIERZONE w placu (2026-09-28), nie szacowane.
>
> **Stan: 6 akcesoriów rozpisanych.** Kosmetyka NIE daje nic do rozgrywki (decyzja Kacpra 2026-09-26) —
> wybór 3 itemów na rundę zostaje jedyną osią mocy, więc akcesoria można projektować czysto pod wygląd.

## Co już jest / czego brakuje

| Miejsce | Rozpisane | Uwagi |
|---|---|---|
| Głowa | czapka tyłem, kask budowlańca | + kapelusz kowboja i garnek (modele Kacpra) |
| Twarz | bandana | |
| Tors | kamizelka odblaskowa | + kamizelka kuloodporna (model Kacpra) |
| Plecy | plecak szkolny | ⭐ kamera patrzy tu przez całą rundę |
| Głowa (uszy) | nauszniki ochronne | |
| Pas / barki / szyja | — | puste, najtańsze do dołożenia |

**9 modeli × 3-4 warianty kolorystyczne = 27-36 pozycji w sklepie.** Nie trzeba więcej na start.

---

# BLOK STYLU — wklej na górze przy KAŻDYM itemie

```
Projektujesz akcesorium do gry na Roblox „ESCAPE LAVA" — arcade survival, gracze
uciekają przed rosnącą lawą po wieżowcach miasta, wysadzają budynki bombami.

=== STYL (obowiązuje dla KAŻDEGO modelu) ===
- Roblox „klocki": bryły proste, twarde krawędzie, zero zaokrągleń poza tymi,
  które naprawdę potrzebne. Wygląd ma pasować do klockowego R15 i do miasta
  zbudowanego z prostopadłościanów.
- LOW POLY. Cel: 300-1500 trójkątów na akcesorium. To ma chodzić na telefonie
  przy 20 graczach naraz.
- PŁASKIE KOLORY, ZERO TEKSTUR. Żadnych gradientów, żadnego wypalonego
  cieniowania, żadnych map normalnych. Kolor = jedna wartość na powierzchnię.
  Rozdziel model na osobne powierzchnie tam, gdzie kolory mają się różnić —
  przemalowywanie kolorów to sposób, w jaki z jednego modelu robimy wiele
  produktów w sklepie.
- Proporcje PRZESADZONE i przysadziste: grubsze, krótsze i bardziej kanciaste
  niż w rzeczywistości. Cienki, realistyczny detal znika na ekranie telefonu.
- SYLWETKA JEST WAŻNIEJSZA NIŻ DETAL. Model ma być rozpoznawalny jako czarny
  obrys przy wielkości miniatury — gra jest nagrywana na TikToka.
- Kamera stoi ZA PRAWYM RAMIENIEM postaci, więc gracz przez całą rundę widzi
  swoje plecy i prawy bok. Detal zostawiaj tam, nie na piersi.
- Kolorystyka nasycona, czytelna w ciepłym pomarańczowym świetle lawy.
  Unikaj ciemnych szarości i brązów, które zlewają się z gruzem.

=== POSTAĆ, POD KTÓRĄ MODELUJESZ (zmierzone, nie szacowane) ===
- Rig: R15 „Block", jednolity dla wszystkich graczy.
- Head: kostka 1,196 × 1,203 × 1,198 studa (traktuj jak 1,2 × 1,2 × 1,2).
- UpperTorso: 2 × 1,6 × 1 studa. LowerTorso: 2 × 0,4 × 1.
- UpperArm 1 × 1,4 × 1 (środek ramienia na x = ±1,5) · LowerArm 1 × 1,2 × 1 ·
  Hand 1 × 0,3 × 1.
- PRZÓD POSTACI TO KIERUNEK −Z. Góra to +Y. Szerokość to X.
- Punkty zaczepienia (lokalnie względem swojej części ciała):
    HatAttachment        (0,  0.6,  0)    na głowie, czubek
    HairAttachment       (0,  0.6,  0)    na głowie
    FaceFrontAttachment  (0,  0,   -0.6)  na głowie, środek przodu twarzy
    NeckAttachment       (0,  0.8,  0)    na UpperTorso, góra
    BodyFrontAttachment  (0, -0.2, -0.5)  na UpperTorso, przód klatki
    BodyBackAttachment   (0, -0.2,  0.5)  na UpperTorso, plecy
    LeftCollarAttachment / RightCollarAttachment — barki

=== TWARDE WYMAGANIA TECHNICZNE ===
1. Model wyląduje w Roblox jako `Accessory`. Główna bryła MUSI nazywać się
   `Handle`, a w środku `Handle` MUSI siedzieć obiekt `Attachment` o nazwie
   DOKŁADNIE takiej jak punkt zaczepienia na ciele (np. `HatAttachment`).
   To nie jest kosmetyka — w naszym systemie ragdolla akcesorium BEZ
   Attachmentu wywala cały skrypt przewracania postaci, czyli psuje grę,
   a nie tylko czapkę.
2. NIC NIE MOŻE DYNDAĆ. Akcesoria są spinane sztywno (kąt 0), więc długie
   paski, łańcuchy, frędzle i peleryny będą sterczeć jak deska i wyglądać
   na błąd. Wszystko ma być krótkie i przylegające.
3. Nie zasłaniaj całej głowy — głowa postaci obraca się za kamerą i to musi
   być widoczne. Zostaw odsłonięty przynajmniej fragment twarzy albo karku.
4. Nie wchodź w prawą dłoń ani przed nią — gracz trzyma tam bombę o gabarycie
   ok. 2,1 × 2,8 × 2,1 studa.
5. Origin/pivot modelu ustaw w punkcie, który ma wylądować na attachmencie
   ciała. Podaj tę pozycję jawnie.

=== CO MASZ ODDAĆ ===
- Model w opisanym stylu, wyśrodkowany i w podanej skali (jednostka = 1 stud).
- Lista powierzchni z przypisanym kolorem (nazwa + RGB), tak żeby dało się je
  potem przemalować na warianty.
- Nazwę attachmentu i pozycję originu.
- Liczbę trójkątów.

=== ITEM DO ZROBIENIA ===
[tu wklej blok itemu]
```

---

# 1. 🦺 Kamizelka odblaskowa

```
ITEM: Kamizelka odblaskowa (hi-vis, budowlana/drogowa)
Zaczepienie: NeckAttachment (na UpperTorso)
Gabaryt docelowy: ok. 2,14 szer. × 1,30 wys. × 1,14 głęb. studa
Origin: środek górnej krawędzi otworu na szyję

Skorupa opinająca tors 2 × 1,6 × 1 z luzem ok. 0,06-0,07 studa na stronę —
ma wyglądać jak narzucona NA postać, nie jak wtopiona w nią. Zaczyna się tuż
pod szyją, kończy nad pasem (nie zakrywa LowerTorso).

Budowa:
- Otwarty przód: dwa panele przednie z pionową szczeliną ok. 0,12 studa
  między nimi, plecy jednolite.
- Wykrój pach: proste, kanciaste wcięcia — żadnych zaokrąglonych rękawów.
- DWA poziome pasy odblaskowe biegnące dookoła (przód, boki, plecy), każdy
  ok. 0,16 studa wysokości, wypuszczone 0,02 studa nad powierzchnię kamizelki,
  żeby czytały się jako osobny materiał bez tekstury.
- DWA pionowe pasy odblaskowe na plecach, od ramion w dół, spotykające się
  z poziomymi (kamera patrzy na plecy — to jest strona, która ma wyglądać).
- Opcjonalnie: prosta, kanciasta kieszeń na lewym panelu przednim.

Kolory (rozdziel jako osobne powierzchnie):
- Korpus: jaskrawy pomarańcz odblaskowy 255,120,20
- Pasy odblaskowe: bardzo jasny srebrnoszary 225,230,235
- Obszycie / szwy (opcjonalnie): ciemniejszy pomarańcz 200,85,10

Warianty do przewidzenia (ten sam mesh, inne kolory): żółty 240,220,40 ·
limonkowy 160,230,60 · czerwony 210,50,45 · niebieski 45,110,200.
```

---

# 2. 🎧 Nauszniki ochronne

```
ITEM: Nauszniki ochronne (przemysłowe, typu strzeleckiego/budowlanego)
Zaczepienie: HatAttachment (na głowie)
Gabaryt docelowy: ok. 1,55 szer. × 0,80 wys. × 0,60 głęb. studa
Origin: środek pałąka w jego najwyższym punkcie

Zakładane na kostkę głowy 1,2 × 1,2 × 1,2. Muszle siedzą TUŻ OBOK głowy,
nie w niej: wewnętrzna ściana muszli na x = ±0,62.

Budowa:
- Pałąk: kanciasty łuk przechodzący przez czubek głowy, ok. 0,16 studa gruby
  i 0,34 szeroki. NIE gładki półokrąg — złóż go z 4-6 prostych odcinków,
  żeby czytał się jak klocek. Górna krawędź pałąka ok. 0,18 studa nad czubkiem.
- Wsuwki regulacji: dwa krótkie, węższe prostopadłościany po bokach pałąka
  tuż nad muszlami — prosty detal, który od razu mówi „sprzęt ochronny".
- Muszle: dwa przysadziste, zaokrąglone prostopadłościany ok. 0,46 × 0,54 × 0,46,
  na wysokości środka głowy (y ≈ 0), wyśrodkowane w osi Z.
- Poduszka uszczelniająca: cieńsza płytka od strony głowy, wypuszczona
  0,05 studa, w innym kolorze — jedyny „miękki" element.

Kolory:
- Muszle i pałąk: mocna czerwień robocza 200,45,40
- Wsuwki regulacji i okucia: ciemny grafit 55,58,62
- Poduszki uszczelniające: czerń matowa 30,30,32

Warianty: żółty 240,200,40 · pomarańcz 255,120,20 · zieleń 40,150,80 ·
grafit 70,74,80.

UWAGA: muszle nie mogą zachodzić na FaceFrontAttachment (0, 0, -0,6), bo w tym
miejscu siada bandana — te dwa akcesoria mają dać się nosić razem.
```

---

# 3. 🧣 Bandana czerwona z wzorem

```
ITEM: Bandana na twarz, czerwona ze wzorem
Zaczepienie: FaceFrontAttachment (na głowie)
Gabaryt docelowy: ok. 1,30 szer. × 0,62 wys. × 1,26 głęb. studa
Origin: środek przedniej ściany bandany

Chusta zasłaniająca DOLNĄ połowę twarzy: od linii tuż pod oczami
(y ≈ +0,10 względem środka głowy) do poziomu podbródka (y ≈ -0,52).
Opina głowę z przodu i z boków, z tyłu zwęża się w węzeł.

Budowa:
- Skorupa opinająca kostkę głowy z luzem 0,04-0,05 studa na stronę.
  Przednia ściana lekko wypchnięta do przodu na środku (ok. 0,04 studa),
  żeby nie była idealnie płaska — sugestia nosa pod materiałem.
- Górna krawędź: NIE prosta linia. Zrób ją lekko łamaną / opadającą ku bokom,
  jak naciągnięty materiał.
- Węzeł z tyłu: mały, kanciasty klocek ok. 0,3 × 0,25 × 0,2 wystający
  ok. 0,15 studa za głowę, plus DWA krótkie, sztywne końce chusty
  (maks. 0,35 studa długości, przylegające do karku — pamiętaj, nic nie dynda).
- Fałdy: 2-3 płytkie, kanciaste zagłębienia biegnące ukośnie po bokach.

WZÓR — rób go GEOMETRIĄ, NIE TEKSTURĄ:
Wzór paisley/bandanowy wymagałby wgrania tekstury na Roblox (opłata +
moderacja + ryzyko odrzucenia), a cała nasza kosmetyka stoi na płaskich
kolorach. Zamiast tego zbuduj wzór jako PŁASKIE, WIELOKĄTNE POLA w drugim
kolorze, wtopione w powierzchnię (nie wypukłe):
- Rząd kanciastych rombów / diamentów wzdłuż górnej krawędzi
- Pas prostych, grubych kresek lub kropek-kwadratów przy dolnej krawędzi
- Wszystko duże i czytelne: najmniejszy element wzoru nie mniejszy niż
  0,08 studa, inaczej zniknie na telefonie
- Wzór ma być widoczny z PRZODU i z BOKU (bok to strona, którą widzi kamera)

Kolory:
- Materiał bandany: czerwień 190,40,40
- Wzór: kość słoniowa 240,235,220
- Węzeł i końce: ta sama czerwień, ewentualnie o 10% ciemniejsza 170,35,35

Warianty: granat 35,55,120 · czerń 40,40,45 · zieleń wojskowa 85,105,60 ·
bordo 120,30,45 — wzór zawsze w kości słoniowej.
```

---

# 4. 🧢 Czapka z daszkiem, noszona tyłem

```
ITEM: Czapka z daszkiem założona TYŁEM DO PRZODU (snapback)
Zaczepienie: HatAttachment (na głowie)
Gabaryt docelowy: ok. 1,30 szer. × 0,58 wys. × 1,76 głęb. studa
Origin: środek czaszy na wysokości czubka głowy

WSZYSTKIE WSPÓŁRZĘDNE NIŻEJ SĄ WZGLĘDEM ŚRODKA GŁOWY (kostka 1,2; czubek
głowy y = +0,6; przód twarzy z = −0,6; tył głowy z = +0,6).

To jest czapka odwrócona: DASZEK WYSTAJE DO TYŁU (kierunek +Z), a regulator
z paskiem siedzi z przodu, nad czołem. To ma być czytelne od pierwszego
spojrzenia — sylwetka z daszkiem sterczącym za głową.

Budowa:
- CZASZA: od y = +0,17 do y = +0,62, szerokość 1,28, głębokość 1,28.
  Lekko kopulasta (środek wyżej o ok. 0,04), ale ZŁOŻONA Z PŁASKICH ŚCIAN —
  nie gładka kula. Dolna krawędź obcięta poziomo, opina głowę z luzem 0,04.
- DASZEK: płytka wychodząca z TYŁU czaszy. Od z = +0,62 do z = +1,08
  (długość 0,46), szerokość 1,02, grubość 0,08, na wysokości y ≈ +0,20.
  Uniesiony o 8-10° ku górze na końcu. Koniec daszka ścięty w łagodny,
  kanciasty łuk (3-4 odcinki proste), nie w półokrąg.
- SPÓD DASZKA to osobna powierzchnia w JAŚNIEJSZYM kolorze — tak wyglądają
  prawdziwe czapki i to jest tani, czytelny detal.
- REGULATOR Z PRZODU (bo czapka jest odwrócona): prostokątny pasek
  0,50 × 0,16 × 0,06 przyklejony do przedniej ściany czaszy na y ≈ +0,22,
  z ≈ −0,63. Na nim rząd 4-5 KWADRATOWYCH dziurek (wgłębienia 0,05).
  Nad paskiem mała szczelina między dwoma panelami czaszy.
- GUZIK na czubku: kostka 0,12 × 0,06 × 0,12 na y = +0,64, x = 0, z = 0.
- PANELE: zaznacz podział czaszy na 6 paneli PŁYTKIMI ROWKAMI (0,02 głębokie,
  0,04 szerokie), biegnącymi od guzika w dół. Bez tego czapka wygląda jak
  kubek nałożony na głowę.

Kolory (osobne powierzchnie):
- Czasza i daszek: czerwień 200,50,45
- Spód daszka: jasna szarość 200,203,208
- Regulator: biel 240,240,242
- Guzik: ta sama czerwień co czasza

Warianty: granat 35,50,95 · czerń 38,38,42 · biel 235,235,238 ·
zieleń 45,140,75 · żółć 240,200,45. Spód daszka i regulator zostają jasne
przy każdym wariancie.

UWAGA NA ZGODNOŚĆ: dolna krawędź czaszy jest na y = +0,17. Muszle nauszników
ochronnych (osobne akcesorium) sięgają góry na y ≈ +0,18 przy x = ±0,62.
Czasza ma szerokość 1,28, czyli kończy się na x = ±0,64 — styka się z nimi
dokładnie na krawędzi. Nie poszerzaj czaszy powyżej 1,30.
```

---

# 5. 🎒 Plecak szkolny

```
ITEM: Plecak szkolny
Zaczepienie: BodyBackAttachment (na UpperTorso)
Gabaryt docelowy: ok. 1,30 szer. × 1,40 wys. × 0,78 głęb. studa
Origin: środek tylnej ściany plecaka (ta, która przylega do pleców)

WSZYSTKIE WSPÓŁRZĘDNE NIŻEJ SĄ WZGLĘDEM ŚRODKA UpperTorso
(tors 2 × 1,6 × 1; plecy na z = +0,5; przód klatki na z = −0,5;
góra torsu y = +0,8; dół y = −0,8).

To jest NAJWAŻNIEJSZY slot w tej grze — kamera stoi za prawym ramieniem
postaci, więc gracz gapi się na ten model przez całą rundę. Detal ma być
na TYLNEJ, zewnętrznej ścianie plecaka, bo to ona jest zwrócona do kamery.

Budowa:
- KORPUS: od z = +0,60 do z = +1,16 (głębokość 0,56), szerokość 1,26,
  wysokość 1,28 (y od −0,72 do +0,56).
  ⚠️ Zaczyna się na z = +0,60, a nie przy samych plecach — pod spodem mieści
  się kamizelka (osobne akcesorium sięgające z = +0,57). Ta szczelina jest
  celowa, nie zamykaj jej.
  Górna krawędź lekko wypukła (klapa), dolne rogi ścięte o 0,08 — plecak ma
  wyglądać na wypchany, nie jak pudełko.
- KLAPA górna: osobna płytka 1,28 × 0,10 × 0,40 nachodząca na korpus od góry,
  zachodząca na tylną ścianę o 0,25 w dół. Pod nią pasek zapięcia z klamrą
  (kostka 0,18 × 0,14 × 0,06) na środku, na y ≈ +0,30, z = +1,18.
- KIESZEŃ ZEWNĘTRZNA: 0,90 szer. × 0,62 wys. × 0,14 głęb., wysunięta do
  z = +1,30, wyśrodkowana w X, dół na y = −0,60.
  Na niej poziomy ZAMEK: listwa 0,82 × 0,07, wypuszczona 0,02, w metalicznym
  kolorze, z suwakiem (kostka 0,10 × 0,10 × 0,06) przesuniętym na prawo.
- SZELKI: dwa pasy, x = ±0,36, szerokość 0,22, grubość 0,09.
  Biegną od górnej krawędzi plecaka (y = +0,50, z = +0,62) ŁUKIEM przez bark
  (najwyższy punkt y ≈ +0,80) i schodzą na przód torsu, kończąc się na
  y ≈ −0,30, z ≈ −0,63.
  ⚠️ z = −0,63 z przodu, a nie −0,50 — szelki muszą minąć kamizelkę.
  ⚠️ Trzymaj się x = ±0,36. Ramiona postaci mają środek na x = ±1,5 i się
  obracają; szelka dalej od środka będzie w nie wchodzić przy chodzeniu.
- UCHWYT na górze: sztywny pałąk 0,30 szer. × 0,10 wys. × 0,12 głęb. na
  y = +0,60, z = +0,88. Krótki, przylegający — nic nie może dyndać.
- KIESZEŃ BOCZNA Z BUTELKĄ (po PRAWEJ stronie postaci, x = +0,70 — bo to ta
  strona, którą widzi kamera): płytka kieszeń 0,30 wys., a w niej butelka:
  walec-graniastosłup 0,22 × 0,45, wystający 0,25 nad kieszeń, z zakrętką
  0,16 × 0,10 w kontrastowym kolorze.
- OPCJONALNIE: linijka albo ołówek wystający 0,20 z kieszeni zewnętrznej —
  jeden element, który mówi „szkolny" bez żadnego napisu.

Kolory (osobne powierzchnie):
- Korpus i klapa: niebieski 45,95,190
- Kieszeń zewnętrzna: ciemniejszy niebieski 32,72,155
- Zamki, suwak, klamra: jasna szarość 195,200,208
- Szelki: ten sam niebieski co korpus
- Butelka: biel 238,240,245, zakrętka czerwień 210,55,50

Warianty: czerwony 195,55,50 · zielony 55,140,70 · czarny 40,40,45 ·
fioletowy 120,70,180 · pomarańczowy 235,130,35.
```

---

# 6. ⛑️ Kask budowlańca

```
ITEM: Kask budowlańca (hełm ochronny)
Zaczepienie: HatAttachment (na głowie)
Gabaryt docelowy: ok. 1,50 szer. × 0,60 wys. × 1,78 głęb. studa
Origin: środek czaszy na wysokości czubka głowy

WSZYSTKIE WSPÓŁRZĘDNE NIŻEJ SĄ WZGLĘDEM ŚRODKA GŁOWY (kostka 1,2; czubek
głowy y = +0,6; przód twarzy z = −0,6; tył głowy z = +0,6).

Budowa:
- CZASZA: od y = +0,16 do y = +0,74, szerokość 1,34, głębokość 1,34.
  Kopuła ZŁOŻONA Z PŁASKICH ŚCIAN (6-8 segmentów), nie gładka półkula.
  Ścianki lekko zbieżne ku górze, żeby czytało się jak hełm, a nie jak miska.
- TRZY PRZETŁOCZENIA (żebra) — to jest detal, który sprawia, że kask wygląda
  jak kask, a nie jak kapelusz. Pasy biegnące PRZÓD-TYŁ po kopule, wypuszczone
  0,06 nad jej powierzchnię, szerokie 0,12:
    * jedno centralne na x = 0
    * dwa boczne na x = ±0,38
  Każde zaczyna się przy przedniej krawędzi czaszy i kończy przy tylnej.
- RONDO: płytka grubości 0,08, na wysokości y od +0,20 do +0,28, obiegająca
  czaszę dookoła, o zmiennej szerokości:
    * PRZÓD (−Z): wystaje 0,28 — do z = −0,95. To jest charakterystyczny
      daszek kasku, ma być najbardziej widoczny.
    * TYŁ (+Z): wystaje 0,14 — do z = +0,81, lekko opadający.
    * BOKI (±X): wystaje TYLKO 0,08 — do x = ±0,75.
  ⚠️ Boki ronda są celowo wąskie i wysokie — patrz UWAGA NA ZGODNOŚĆ niżej.
  Krawędź ronda lekko podwinięta w dół (0,04) po obwodzie.
- POLE NA NAKLEJKĘ: płaskie, lekko wpuszczone pole 0,40 × 0,22 na przedniej
  ścianie czaszy, na y ≈ +0,46. Osobna powierzchnia — to jest miejsce na
  kolor akcentu i na przyszłe warianty.
- WNĘTRZE: od spodu widać ciemną więźbę — wystarczy jedna ciemna powierzchnia
  wpuszczona 0,06 w głąb czaszy, żeby kask nie wyglądał na wydrążoną skorupę,
  kiedy patrzy się na postać od dołu (a gracze patrzą, bo skaczą z dachów).

Kolory (osobne powierzchnie):
- Czasza, żebra i rondo: żółć ostrzegawcza 245,205,35
- Pole naklejki: pomarańcz 235,120,30
- Wnętrze / więźba: ciemny grafit 52,55,60

Warianty — i one mają ZNACZENIE, bo na prawdziwej budowie kolor kasku to
funkcja; warto to wykorzystać w opisach w sklepie:
- biel 238,238,240 — kierownik budowy
- pomarańcz 235,120,30 — drogowcy
- niebieski 50,110,200 — elektryk
- czerwień 195,50,45 — straż / ratownik
- zieleń 55,140,70 — inspektor BHP

UWAGA NA ZGODNOŚĆ (ważne — to jest ten sam zestaw): kask ma być noszony
RAZEM z nausznikami ochronnymi. Muszle nauszników zajmują x od ±0,62 do
±1,08, a ich górna krawędź jest na y ≈ +0,18. Dlatego boczne rondo kasku:
(a) wystaje tylko 0,08 (do x = ±0,75), i (b) leży na y ≥ +0,20, czyli NAD
muszlami. Nie poszerzaj i nie obniżaj bocznego ronda — inaczej te dwa
akcesoria wejdą w siebie, a to najbardziej oczywisty zestaw w całym sklepie.
```

---

# KOLIZJE MIĘDZY AKCESORIAMI — policzone, nie zgadnięte

Gracz będzie nosił kilka rzeczy naraz. Te pary trzeba było rozsunąć w wymiarach:

| Para | Problem | Rozwiązanie (już w promptach) |
|---|---|---|
| Kask × nauszniki | Rondo wchodziło w górę muszli | Boczne rondo zwężone do 0,08 i podniesione na y ≥ +0,20 |
| Plecak × kamizelka | Kamizelka sięga z tyłu z = +0,57 | Korpus plecaka startuje z = +0,60, szelki z przodu po z = −0,63 |
| Czapka × nauszniki | Stykają się na krawędzi (x ±0,64 vs ±0,62) | Nie poszerzać czaszy powyżej 1,30 |

**Zasada na przyszłość:** każdy nowy model na głowę sprawdzić przeciwko nausznikom (zajmują `x` od ±0,62 do ±1,08, góra `y ≈ +0,18`), a każdy na plecy — przeciwko kamizelce (`z = +0,57`).

---

# Co zostaje po stronie Kacpra

- **Wygląd i ocena** — czy to dobrze wygląda, decyduje Kacper.
- **Opakowanie w `Accessory`** w Studio: `Handle` + `Attachment` o właściwej nazwie. ⚠️ Akcesorium bez Attachmentu **wywala skrypt ragdolla**, czyli psuje grę, a nie tylko czapkę.
- **Zapis placu (Cmd+S)** — akcesoria żyją w pliku `.rbxl`, nie w repo. Rojo ich nie dowozi.
- **Warianty kolorystyczne** — jedna wartość na powierzchnię, zero nowych assetów.

⚠️ **Nauszniki, bandana, czapka i kask zależą od kształtu głowy.** Wymiary są z OBECNEJ głowy (dynamiczna, `MeshPart` + `FaceControls`, kostka 1,2). Jeśli kiedyś przejdziemy na klasyczną klockową (potrzebną, gdyby twarze miały być towarem — etap ③), te cztery plus kapelusz i garnek trzeba dopasować od nowa. Przy sześciu modelach to godzina, przy piętnastu — wieczór.
