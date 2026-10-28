# Co zostało do release’u

Aktualizacja: **23.10.2026**. Stan implementacji i dowody: [STATUS](STATUS.md). Testy wykonuje Kacper według [TESTY](TESTY.md); samo napisanie/skompilowanie kodu nie zalicza testu.

## Najpierw akceptacja obecnej gry

- [ ] **Destrukcja T1–T7 dwa razy bez błędu pod rząd**; sprawdzić również pozostałe budynki, rekwizyty, auta, beczki i twarde ruiny. Zebrać aktualne logi `[Collapse]` / `[Destr]`. Po zaliczeniu zamrozić zakres destrukcji.
- [ ] Loadout i zapis: wybór tylko w lobby, trzy stałe sloty, brak equipa spoza loadoutu, zachowanie danych po ponownym wejściu.
- [ ] Pełna pętla kilku rund: przygotowanie, 3-2-1, aktywacja ruchu/itemów, FINISHING, nagroda raz, cleanup, odbudowa i dołączanie w trakcie.
- [ ] Nowe elementy 18–23.10: start klienta, loading v2, UI, sklep/kadry/stałe światła i powrót kamery po respawnie, RPG/odrzut/chwyt, napój/picie/efekt, beczki i zapłon od F.
- [ ] Test zapisu przy wyjściu i zamykaniu serwera oraz test na wolnym urządzeniu/sieci. Dawny test samego fall damage z 19.09 jest zaliczony 01.10; nie wymaga powtórzenia jako zaległość, chyba że nowa zmiana dotknie tej mechaniki.
- [ ] Naprawić zgłoszone usterki i zapisać wyniki; commity na prośbę Kacpra.
- [ ] Przed publikacją podbić `Config.UI.Version` (napis w prawym dolnym rogu, od 27.10).

## Implementacja i przygotowanie brakujących elementów

| Zadanie | Właściciel / uwagi |
|---|---|
| Sterowanie na telefonie: sprint, push, potwierdzenie/obrót mostu | Kacper: UI; agent: logika. Sprawdzić też celowanie i użycie wszystkich itemów na dotyku. |
| Anty-cheat — paczka 6 | Agent; plan w REVIEW. Decyzje cofnięcie → kill → kick i pion po ~1 s są zamknięte. Uwzględnić ragdoll, hak, lawę i ruchome platformy. |
| Start przy 30–50 graczach | Agent: obecnie sekwencyjne ładowanie postaci; Kacper: multi-spawn. `SpawnPoints` pusty w Edit 23.10, działa fallback. Docelowy limit miejsca wymaga decyzji. |
| Ruch głowy i odporność startu serwera | Agent: ograniczenie odbiorców HeadAim, obsługa błędu startu usługi zgodnie z zależnościami. |
| Obciążenie destrukcji/odbudowy | Pomiar w grze; M-7 (koszt faktycznych kawałków) i M-13 z REVIEW pozostają otwarte. Odbudowa tylko naruszonych jednostek jest już zaimplementowana. |
| C4 (= sticky bomb) | 25.10 w kodzie (`C4Service`, `C4Controller`, definicja `c4`). Przyklejanie i G sprawdzone w pierwszym teście Kacpra; **rzut** (zamiast klikania) i ikona `rbxassetid://103956142743404` 25.10 — NIEPRZETESTOWANE. Model i przycisk postawione przez MCP 25.10 (Cmd+S). |
| Hak pod nogi | Agent: odrzucenie nieużytecznego lotu przed zużyciem sztuki; dotychczas odłożone. |
| Gest pchnięcia na produkcji | Kacper: opublikować `Push_TwoHands_R15`; agent: wpiąć ID. Obecnie `AnimationId = 0`, tylko podgląd Studio. |
| Dźwięki | Kacper: ID pięciu dźwięków destrukcji i strzału RPG; agent: wpięcie. Łyk napoju opcjonalny. |
| Bake budynków w placu | Przed TRYB 3 sprawdzić zaokrąglenia 0,001 i brak walidacji `MapRevision`; obecnie brak zapisanych danych w Edit. Po bake zweryfikować zgodność z geometrią. |
| Uprawnienia dev po UserId | Agent + UserId Kacpra. Przed wydaniem tryb dev wyłączony niezależnie od tego zadania. |

Sprzątanie starszej destrukcji poza budynkami: najpierw ustalić jej rzeczywistych użytkowników. Wspólna walidacja remote’ów, usunięcie duplikatów/martwego kodu i podział dużych plików to zaległe paczki 8–9. Nie są dowodem awarii i nie wymagają automatycznie pełnego refaktoru przed betą; zakres do wyboru po testach.

## Otwarte decyzje i drobny polish

- [ ] Endgame na najwyższych dachach: ocena na produkcyjnej krzywej lawy z prawdziwymi graczami. Stare wyliczenia dla faz są historyczne.
- [ ] Farma kill reward 25$ między dwoma kontami — ustalić, czy potrzebne ograniczenie.
- [ ] Docelowy limit graczy i rozmieszczenie spawnów. `Config.Game.MaxPlayers = 20` nie ustawia limitu miejsca.
- [ ] Kotwica `HUD.KillMessage.Body` (dawny wpis o wzroście od rogu) i ewentualny panel SETTINGS: ocena/zakres Kacpra. Nie przywracać panelu wyboru grafiki — tryby usunięte.
- [ ] Latarnie świecące pod ulicę i szkło aut/automatów/przystanku — odłożone decyzje wizualne.
- [ ] Sklep: ocenić kadry po zmianach 23.10. **Marker haka nie jest wymagany**: `UseCameraMarkers = false`.

Loadout, energy drink, RPG (strzał + wybuch + efekty/odrzut), kill message i win message są już zaimplementowane. **Rocket jump wycofany**, brak zadania „RPG etap 2 = rocket jump”. Kosmetyki/sklep skinów/daily rewards/monetyzacja to dalsze kierunki, nie dopisana automatycznie bramka publikacji.

## Tuż przed publikacją

- [ ] `Config.Lava.RoundDuration = 80`, `SpeedStart = 0`, `SpeedEnd = 3.0` — zmienić razem (przyrost ~120 studów). Nie odtwarzać `Lava.Phases`.
- [ ] `Config.Dev.Enabled = false` i `InfiniteItemsForAll = false`.
- [ ] `Config.Game.MinPlayers = 2`.
- [ ] `Config.Structure.Collapse.Debug = false` i `Config.Destruction.Debug = false`.
- [ ] Ustawić limit graczy w ustawieniach miejsca Roblox.
- [ ] Zapisać plac **Cmd+S**, potwierdzić zgodność kodu Studio z wersją przeznaczoną do wydania; dopilnować modeli i GUI, których nie ma w repo.
- [ ] Test z kilkoma osobami na prawdziwym serwerze, także telefonami: zapis, wszystkie itemy, własne wybuchy, animacja F, lawa/EditableMesh lub fallback, kilka rund, odbudowa i wydajność.
- [ ] Publikacja po akceptacji Kacpra.
