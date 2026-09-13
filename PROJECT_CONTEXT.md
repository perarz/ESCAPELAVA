# ESCAPE LAVA — kontekst projektu (dla asystenta)

> Dokument dla asystenta pomagającego w organizacji pracy (TODO, planowanie, decyzje).
> Celowo bez szczegółów kodu — od logiki gry jest Claude Code w repo.
> Stan na: 2026-09-13.

---

## Czym jest ta gra

**ESCAPE LAVA** — gra na Roblox, arcade survival. 15-20 graczy na serwerze. Lawa zalewa
mapę od dołu coraz szybciej, gracze uciekają w górę po wieżowcach miasta ("Downtown"),
kupują itemy (bomby do wysadzania przeciwników i terenu, mosty do budowania przepraw),
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

Zasada: Claude pyta o decyzje designowe zanim koduje; Kacper nie musi dotykać kodu.

## Co jest GOTOWE (z perspektywy gracza)

- **Pełna pętla rundy**: lobby → odliczanie → runda z lawą przyspieszającą w fazach →
  nagrody → restart. Mapa naprawia się sama po każdej rundzie.
- **Bomba** (50$): rzut, odliczanie z migającym lontem, rani i odrzuca graczy (ragdoll),
  zabójstwa nagradzane kasą. **UWAGA: sam wybuch został skasowany 11.08** (decyzja: nie
  podobał się, budujemy od nowa) — dziś detonacja jest niewidoczna i nie rusza mapy.
  Zostało: rzut, obrażenia, odrzut, ragdoll, wstrząs ekranu. Do zaprojektowania od zera:
  jak wybuch wygląda i czy/jak niszczy teren.
- **Most** (100$): budowanie przeprawy z podglądem "ducha", obracanie. Sabotaż PvP
  (wysadzanie mostów) wróci razem z nowym wybuchem.
- **Push (F)**: spychanie przeciwników z cooldownem 4s — kill credit jak wpadną w lawę.
- **Kasa**: zbierana z mapy (przyciąganie magnetyczne + animacja lotu ze złotym trailem),
  za zabójstwa (25$), za przetrwanie rundy (100$), popupy "+10$", licznik jako ozdobne
  cyfry z teksturą studs.
- **Sklep jako NPC w lobby** (przebudowany 12.09): podchodzisz do sprzedawcy, wciskasz E,
  kamera płynnie jedzie po wystawie z itemami i celuje w wybrany, a na dole panel z nazwą,
  ceną, opisem i przyciskiem KUP. Przewijanie strzałkami / A-D / scrollem. Zakup
  weryfikowany odległością od sprzedawcy, więc nie da się kupować w trakcie rundy.
  Dodanie nowego itemu do sklepu = postawienie dwóch obiektów w Studio, bez tykania kodu.
- **Hotbar** z equipem itemów (klawisze 1-5, białe podświetlenie wybranego slotu).
- ~~Daily rewards~~ — **skasowane 12.09**, bo stare UI się nie podobało. Do zrobienia od nowa.
- **Ruch**: sprint (Shift) ze staminą, kamera 3rd person z płynnym wygładzaniem,
  dynamiczny FOV, wstrząsy ekranu przy trafieniach, kurz przy lądowaniu, obracanie głowy
  za kamerą (widoczne dla innych).
- **Klimat**: lawa z unoszącymi się iskrami i dymem, "żar" na ekranie gdy gracz jest
  nisko nad lawą, słup pary przy śmierci w lawie.
- **Pasek staminy przy postaci** (12.09): nie element HUD, tylko pionowy wskaźnik unoszący
  się obok Twojej postaci w świecie — widzi go **tylko właściciel**. Pokazuje się sam przy
  sprincie i chowa po naładowaniu, ze sprężystą animacją; kolor idzie od niebieskiego przez
  żółty do czerwonego w miarę ubywania sił.
- **HUD**: killfeed, banner zwycięzców, paski cooldownów; **pełne skalowanie na każdy
  monitor** (projekt w px przy 1440p, reszta skaluje się automatycznie, elementy przypięte
  do krawędzi/rogów ekranu).
- **Zaplecze**: zapis postępu graczy (kasa/itemy/winy/streak) odporny na awarie,
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

**A. Wizja ustalona 12.09 — kolejny duży blok pracy (jeszcze nierobione):**
- **Ekwipunek i loadout**: hotbar skrócony do **3 slotów**, a gracz wybiera 3 itemy
  z docelowych **6**. Sens: zmusić do decyzji (mobilność vs atak vs wsparcie) zamiast
  brania samych ułatwień w bieganiu. Daje 20 różnych zestawów.
- **Drugie stoisko — skiny**: osobny NPC, kamera przesuwa się na Twoją postać
  w przebieralni, przewijasz i kupujesz. **Uwaga: to nie jest "drugi sklep", tylko nowy
  system** (zapis posiadanych skinów, zakładanie na postać przy odrodzeniu, assety) —
  robić dopiero po loadoucie.
- **Daily rewards od nowa** jako UI.
- **4 nowe itemy** do kompletu 6. Claude przynosi propozycje, Kacper wybiera.

**B. Otwarte pytanie designowe**: przy obecnych liczbach lawa w 80-sekundowej rundzie
podnosi się tylko o ~120 studów, więc wyższe piętra są od niej bezpieczne z definicji —
czyli wejście na najwyższy budynek to darmowe przetrwanie. Do rozstrzygnięcia przed
budową mapy: czy lawa ma dogonić szczyt, czy wież ma być kilka podobnej wysokości,
czy szczyt ma być świadomą pułapką (tłum + bomby + walące się piętra).


0. **System destrukcji v2** — stary wybuch skasowany 11.08, tego samego dnia zaprojektowany
   nowy (plan zatwierdzony: `DESTRUCTION_PLAN.md` w repo). Cel: topka Roblox — party pękają
   na nieregularne kawałki (dziury w ścianach), szyby sypią się z sąsiednich budynków,
   filary padają od kilku bomb z widocznymi pęknięciami, gruz przygniata graczy (kill
   "crushed"), a w etapie 4 całe sekcje budynków się walą, gdy filary padną.
   **WSZYSTKIE 5 ETAPÓW ZAIMPLEMENTOWANE (11-12.08).** Etap 1 (pękanie ścian, dziury,
   gruz-platformy, nowe VFX) przetestowany i przyjęty; zgłoszone wiszące płyty naprawione.
   Etapy 2-5 czekają na test: szyby i filary, osłona za ścianami, spadanie niepodpartych
   pięter, pękanie gruzu przy upadku, przygniecenia, kolaps całych sekcji budynku po
   filarach z ostrzeżeniem, ślady opalenia. **Zostaje: dźwięki (assety Kacpra — 5 pól
   w konfiguracji, kod gotowy) i balans po testach.**
   Do testu Kacper stawia: party Material Glass (szyby) i party z tagiem "Pillar"
   (Tag Editor) — najlepiej 4 filary na piętro, żeby zobaczyć creak przy 2 i kolaps przy 3.
1. **Mapa Downtown** — NAJWIĘKSZY BRAKUJĄCY ELEMENT. Kacper buduje w Studio: 10-15
   budynków 3-8 pięter, punkty spawn (multi-spawn), markery spawn kasy. Bez mapy nie ma gry.
   **Zasady budowania POD NOWĄ DESTRUKCJĘ** (pełny kontrakt w `DESTRUCTION_PLAN.md`):
   każdy part `Anchored = true`; geometria pod `Workspace.Map`; budynek = folder;
   konstrukcja ze zwykłych Part (Union/MeshPart nie pękają); szyby = Material Glass;
   filary = tag `Pillar`. Kafelkowanie 6×6 JUŻ NIEPOTRZEBNE — system tnie party w runtime,
   ściany mogą być dużymi panelami (mniej roboty, lepszy FPS).
2. **Assety Studio pod istniejące mechaniki** (kod ma fallbacki, ale docelowo Kacper
   stawia swoje): model kasy (paczka banknotów?), szablon mostu, szablony UI
   (popup kasy, paski cooldownów — do ostylowania).
3. **Monetyzacja (Day 5)**: gamepass VIP, dev producty (kup kasę za Robuxy) — do
   zaprojektowania oferta i ceny, potem implementacja.
4. **Pozostałe itemy** (opcjonalnie przed launchem): hook (wciąganie się), sabotage,
   shield — system jest gotowy na dokładanie.
5. **Polish przed launchem (Day 6)**: dźwięki (assety = Kacper), eventy losowe
   (spadające kule ognia, wiatr) — pomysły z GDD, do decyzji czy w v1.0.
6. **Launch (Day 7)**: closed beta z ekipą → publish → TikToki (formaty z GDD sekcja 14).
   Przed publishem: MinPlayers 1→2, test pełnej pętli na żywym serwerze.
7. **Test pod obciążeniem** (przed/tuż po launchu): audyt kodu jest zrobiony (11.08),
   zostaje sprawdzenie na żywym serwerze z ekipą — zapis danych przy 20 graczach,
   wyłączanie serwera. Koszt fizyki przy kilku bombach naraz wraca na listę dopiero
   z nowym systemem wybuchów (pkt 0).

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

- Kod w repo Git (`C:\Users\User\Desktop\ESCAPELAVA`), synchronizacja do Roblox Studio
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
- Dokument referencyjny dla AI kodującego: `CLAUDE.md` w repo (pełny stan techniczny).

## Kluczowe liczby (balans)

- Runda: 5s spawn + 20s easy + 20s mid + 20s hard + 15s endgame = 80s. Lobby 15s.
- Lawa: 0.6 → 1.2 → 2.0 → 3.0 stud/s.
- Bomba 50$ (odpalenie 2.5s, zasięg rażenia graczy 22, zasięg niszczenia terenu 20),
  most 100$, push F co 4s.
- Nagrody: przetrwanie 100$, kill 25$, kasa z mapy 10$/szt, daily 50-500$.
- Start gracza: 100$ na dzień dobry.
