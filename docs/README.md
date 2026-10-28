# ESCAPE LAVA — mapa kontekstu

Aktualizacja: **23.10.2026**. Repo zawiera kod i dokumentację; mapa, modele i większość UI żyją w placu Roblox Studio. Sam `rojo build` nie odtworzy pełnej gry z assetami.

| Potrzeba | Dokument |
|---|---|
| Zasady pracy agenta | [AGENTS.md](AGENTS.md) — przeczytać w całości; [CLAUDE.md](CLAUDE.md) ma tę samą zasadę wejścia |
| Bieżący stan i potwierdzenia | [STATUS.md](STATUS.md) — jedno źródło statusu projektu |
| Co zostało do publikacji | [DO_RELEASE.md](DO_RELEASE.md) |
| Co Kacper sprawdza w Play | [TESTY.md](TESTY.md) — `[x]` oznacza zapisane potwierdzenie, nie sam kod |
| Własność stanu, API i pułapki | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Nazwy i obiekty w placu | [STUDIO_CONTRACT.md](STUDIO_CONTRACT.md) |
| Decyzje produktu, loadout i dalszy rozwój | [ROADMAP.md](ROADMAP.md) |
| Krótki kontekst do planowania | [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) |
| Destrukcja, wcześniejsze podejścia i logi | [DESTRUCTION_PLAN.md](DESTRUCTION_PLAN.md) |
| Audyt z 29.09 i stan paczek | [REVIEW_2026-09-29.md](REVIEW_2026-09-29.md) |
| Wygląd UI / gesty itemów | [UI_RULES.md](UI_RULES.md) / [ITEM_EQUIP_PLAN.md](ITEM_EQUIP_PLAN.md) |
| Pomysły na akcesoria | [AKCESORIA_PROMPTY.md](AKCESORIA_PROMPTY.md) — briefy, nie gotowy system kosmetyków |
| Plan sklepu i garderoby COSMETICS | [COSMETICS_PLAN.md](COSMETICS_PLAN.md) — uzgodnienia 26.10, dostępne modele i otwarte decyzje; etap planowania |
| Historia / wynik porządków | [HISTORY.md](HISTORY.md) / [CONTEXT_AUDIT_2026-10-23.md](CONTEXT_AUDIT_2026-10-23.md) |
| Pełny przegląd kodu 25–26.10 | [CODE_REVIEW_2026-10-26.md](CODE_REVIEW_2026-10-26.md) — poprawki, pokrycie, ograniczenia i dalsze usprawnienia |

Kolejność rozstrzygania rozbieżności: najnowsza decyzja Kacpra → bieżący kod (co jest zaimplementowane) / odczyt placu (co istnieje) → zapisane wyniki testów (co potwierdzone) → plany i historia. Kod ani odczyt Edit nie potwierdzają działania w rozgrywce. Nie przepisywać statusu w kilku plikach; odsyłać do STATUS i TESTY.

Rojo: `rojo serve` synchronizuje kod do istniejącego placu. `rojo build -o /tmp/ESCAPELAVA.rbxlx` sprawdza złożenie projektu kodowego. Zgodność ze Studio sprawdzać po `.Source`, nie przez `require` modułów z MCP. Play uruchamia i testuje Kacper.
