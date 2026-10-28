# ESCAPE LAVA — kontekst do planowania

Aktualizacja: **23.10.2026**. Ten dokument opisuje grę i sposób pracy. Jedno źródło bieżącego statusu: [STATUS](STATUS.md). Zadania do wydania: [DO_RELEASE](DO_RELEASE.md), potwierdzenia rozgrywki: [TESTY](TESTY.md).

## Gra i cel

Roblox arcade survival w mieście Downtown. Gracze uciekają na kolejne piętra przed rosnącą lawą, wysadzają teren, budują mosty, używają haka i spychają rywali. Docelowa skala projektu to kilkuset graczy concurrent na wielu serwerach; rozważany limit pojedynczego serwera to 30–50, ale jego ustawienie i gotowość pod obciążenie nie są potwierdzone. W kodzie jest `MaxPlayers = 20`, które nie ustawia limitu miejsca.

Cel biznesowy: szybkie wydanie i zarabianie Robuxów jako przygotowanie do większego projektu Sword RPG, organiczny marketing na TikToku. Dawne „7–14 dni produkcji” było pierwotnym założeniem, nie aktualnym terminem release’u. KPI z GDD (D7 retention 8%, ARPU 25 R$, 30 tys. wizyt/miesiąc) to cele, nie osiągnięte wyniki.

## Pętla i możliwości gracza

Lobby **25 s** na zakupy/ekwipunek → przygotowanie i teleport pod zasłoną → **3-2-1** na mapie → runda projektowo **80 s** z płynnie przyspieszającą lawą → **3 s końca**, nagroda ocalałym → zasłona, naprawa naruszonych części mapy → **10 s po rundzie** → lobby. Aktualnie runda jest wydłużona do **240 s** na testy. Nie ma faz Easy/Mid/Hard/Endgame.

Gracz posiada zapas itemów i wybiera **3 stałe sloty loadoutu** w panelu Inventory **wyłącznie w lobby**. Dostępne w kodzie: bomba 50$, most 100$, hak 40$, energy drink 25$, RPG 75$, C4 60$ (25.10 = sticky bomb: rzucasz do 3 ładunków, przyklejają się do ścian i podłóg, odpalasz wszystkie naraz klawiszem G albo przyciskiem; rzut do testu). Napój przez 10 s daje nieskończoną staminę, chód +3 i oprawę złota; sprint pozostaje bez zmiany. RPG leci prosto, wybucha słabiej od bomby i rani też strzelca. Rocket jump wycofany.

Destrukcja v4 jest na wszystkich 10 budynkach. Duże bryły spadają fizyką i mogą tworzyć platformy; lokalne drobne odłamki są tylko obrazem, bez kolizji. **Gruz nie rani**. Upadek i wybuchy ranią normalnie; lawa zabija po około 7 s łącznego kontaktu z pełnego HP, da się z niej wypłynąć. Po śmierci około 2 s ragdollu i powrót do lobby. Nie ma domyślnej regeneracji HP.

Nagrody: 100$ za przetrwanie, 25$ za kill, 10$ za pickup, 100$ na start. Komunikat zabójstwa widzi zabójca, „YOU SURVIVED!” tylko ocalały. UI i opisy po angielsku.

## Współpraca i granice

- Kacper decyduje o designie, buduje mapę/UI/modele/assety w Studio i **testuje Play**. Agent pisze logikę i dostarcza konkretną listę sprawdzeń.
- Agent nie uruchamia ani nie zatrzymuje Play. Odczyt Edit i zgodność źródeł pomagają w diagnozie, lecz nie dowodzą działania w grze.
- Nowe mechaniki/refaktory: pytania i plan zgodnie z [zasadami projektu](CLAUDE.md), potem implementacja. Nie wybierać za Kacpra architektury ani nie dokładać scope’u.
- Maks. 2–3 h pracy Kacpra dziennie; po 2 h proponować przerwę, bez nocnego przeciągania.
- Wygląd: klasyczne UI, czarne obrysy, cienie, Fredoka; ekran ładowania ma wyjątek Montserrat Heavy. Dokładne zasady w UI_RULES.

## Co dalej

Obecny problem release’u to brak pełnej akceptacji testowej i kilka braków implementacji. Kolejność: testy (w tym dwa T1–T7) → poprawki → telefon / anty-cheat / skala → dokończenie wybranej zawartości → produkcyjna konfiguracja → test z ekipą i publikacja. Pełna lista w DO_RELEASE; nie przepisywać jej tutaj.

Sklep kosmetyczny i garderoba są już w trakcie dopracowywania po wdrożeniu; uzgodniony zakres i punkt wznowienia w [STATUS](STATUS.md), plan w [COSMETICS_PLAN](COSMETICS_PLAN.md). Nie traktować ich jako niezaczętej propozycji. Daily rewards i monetyzacja pozostają dalszymi kierunkami wymagającymi wyboru zakresu. Kosmetyka bez bonusów; dawny plan pancerzy nie stanowi zatwierdzonego zadania do v1.0.

Świadomie poza v1.0: voting map, lobby parkour, pożary jako mechanika, trzęsienia, blackout, bounty, kradzież monet, king zone, niewidzialne trapy, łamliwe podłogi, windy, tunele, gejzery lawy. Ogień wraków/beczek jest efektem, nie pożarem rozprzestrzeniającym się po mapie.

## Repo i plac

Źródła Luau synchronizuje Rojo. Mapa, UI, rig, modele itemów, materiały i animacja F żyją w placu i wymagają **Cmd+S**. Samo repo nie odtworzy całej gry. GitHub: `perarz/ESCAPELAVA`; ostatni sprawdzony lokalny commit i lokalne zmiany są w STATUS. Nie zakładać, że lokalny commit został wypchnięty. Commit/push tylko na prośbę Kacpra.

Stare rozbudowane opisy postępu, rigów, wyglądu i odrzuconych prób zachowano w [archiwum](archive/2026-10-23/PROJECT_CONTEXT.md). Nie używać ich jako listy aktualnych zadań.
