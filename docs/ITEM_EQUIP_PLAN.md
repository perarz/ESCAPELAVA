# Wyciąganie itemów — 20.10.2026

> **Stan 23.10:** wdrożone; najnowsze wymagania w tabeli „Naturalniejszy chwyt” poniżej. Bomba/hak/blueprint 0,3 s, RPG 0,7 s i stały chwyt oburącz. Pierwotne 0,35 s / oddanie chwytu Animatorowi to historia etapów. Play nadal według TESTY, commit `0d6c63c` obejmuje tę pracę.

Decyzje Kacpra: bomba i hak przy biodrze/kieszeni, blueprint zza pleców; krótko (~0,35 s), subtelnie, również w ruchu i skoku. Użycie dostępne natychmiast i przerywa gest.

Plan przed implementacją:
- `ItemEquipController` jest jedynym właścicielem kosmetycznego gestu. Obserwuje istniejące Tools w postaciach wszystkich graczy; serwisy pozostają właścicielami equipowania i używania.
- Warstwa na `Motor6D.Transform`: zdejmowana w PreAnimation, dodawana po Animatorze w PreSimulation. Bez zapisów C0 (head tracking), prędkości, korzenia i nóg. Pozy ramienia, łokcia, nadgarstka oraz delikatny skręt Waist.
- `Config.ItemEquip` zawiera czas, klatki pozy i mapowanie BombTool/GrappleTool/BlueprintTool. Brak nowych obiektów wymaganych w Studio, asset ID i RemoteEventów. Widoczność innych postaci wynika z replikacji istniejącego Toola, bez ruchu sieciowego co klatkę.
- Bomb/Grapple/Bridge/Push kontrolery wołają `cancel()` przed wysłaniem akcji. Zmiana Toola zastępuje gest; usunięcie Toola, śmierć, ragdoll, koniec rundy, respawn i wyjście gracza sprzątają stan i nałożone przesunięcia. Brak kompletu stawów = brak gestu, mechanika działa dalej.
- Weryfikacja: budowa Rojo, kompilacja i zgodność źródeł w Edit. Play wyłącznie Kacper: trzy itemy z miejsca/w biegu/w skoku, natychmiastowe użycie, szybkie zmiany, push, ragdoll/respawn, drugi gracz.

## Aktualizacja 21.10 — RPG

Decyzje Kacpra: RPG zza ramienia, 0,7 s; pozostałe gesty trochę krótsze (0,3 s zamiast 0,35 s). `ItemEquipController` nadal jest jedynym właścicielem gestu; osobny profil `Rpg` i `Config.ItemEquip.ProfileDurations.Rpg` rozszerzają istniejący kontrakt bez nowych obiektów Studio ani remote'ów. RPG: sięgnięcie nad prawe ramię, wyciągnięcie do przodu i płynne oddanie chwytu Animatorowi. Natychmiastowy strzał nadal przerywa gest; sprzątanie przy zmianie itemu/ragdollu/śmierci zostaje wspólne.

Budowa Rojo i kompilacja obu zmienionych źródeł w Edit przeszły; sumy źródeł Studio zgodne z dyskiem. Bez Play — do sprawdzenia przez Kacpra:
- RPG z miejsca, w biegu i w skoku: gest trwa 0,7 s, ręka sięga za prawe ramię i wraca do chwytu; ocenić przenikanie wyrzutni przez głowę.
- Bomba, hak i blueprint: krótsze wyciągnięcie (0,3 s).
- Strzał natychmiast po wybraniu RPG oraz szybkie RPG → bomba → RPG: brak blokady i pozostawionej pozy ręki.
- Ragdoll/śmierć w trakcie gestu oraz widok drugiego gracza: poprawne sprzątanie i widoczny gest.

## RPG oburącz — 21.10

Na prośbę Kacpra RPG pozostaje trzymane oburącz po wyciągnięciu: prawa ręka na uchwycie, lewa pod lufą. Właścicielem obu ramion pozostaje `ItemEquipController`; `Config.ItemEquip.HoldPoses.Rpg` zawiera pozy dopasowane obliczeniowo do stawów `StarterCharacter` i obecnego chwytu wyrzutni. Podparcie narasta w końcowej części gestu (`HoldBlendStart`/`HoldBlendEnd`), wyciąganie nadal 0,7 s. Bez zmian serwera, remote'ów i kontraktu obiektów Studio.

Stan obserwacji Toola trwa do jego usunięcia, śmierci lub końca rundy. Strzał przerywa samo wyciąganie, zachowując chwyt, gdy RPG nadal jest wyposażone. Ragdoll, siedzenie, drabina i pływanie zawieszają pozę; po wyjściu z tych stanów chwyt wraca bez powtarzania wyciągania. Animacje o priorytecie Action lub wyższym mają pierwszeństwo (subskrypcja Animator.AnimationPlayed, także dla innych graczy). PushController podaje dodatkowo długość swojej animacji do `cancel`, obejmującą wygaszenie. Dołączenie do postaci z już trzymanym RPG nakłada sam chwyt. Usuwanie nakładki w PreAnimation i brak zapisów C0 pozostają bez zmian.

Budowa Rojo, kompilacja trzech zmienionych źródeł w Edit i zgodność sum Studio/dysk potwierdzone. Play wyłącznie Kacper: lewa dłoń pod lufą w staniu/biegu/skoku; strzał z zapasem rakiet zachowuje podparcie; ostatnia rakieta i zmiana itemu uwalniają obie ręce; F odtwarza pełne pchnięcie i wraca do chwytu; ragdoll/respawn i drugi gracz bez zablokowanych ramion.

**21.10 — poprawka po zgłoszeniu „coś się gryzie”:** w porównaniu `AnimationPriority.Value >= Action.Value` priorytet `Core` (wartość 1000, faktycznie NAJNIŻSZY) błędnie zawieszał chwyt RPG. Odczyt `StarterCharacter.Animate` potwierdził, że stanie/bieg używają właśnie `Core`; `toolnone` używa `Idle`. Warunek teraz jawnie dopuszcza tylko Action/Action2/Action3/Action4. To potwierdzony błąd warunku, nie diagnoza całego wyglądu. Budowa i kompilacja przeszły; potrzebny ponowny Play Kacpra: RPG w staniu i biegu ma zachować chwyt, F ma zwolnić ramiona i oddać chwyt po animacji.

## Naturalniejszy chwyt / RPG przez brzuch — 21.10

Zbiór obowiązujących wymagań po feedbacku:

| Wymaganie | Aktualne rozwiązanie |
|---|---|
| Wyciąganie zza ramienia, 0,7 s | Dotychczasowy profil Rpg i jego czas pozostają |
| Reszta gestów krócej | Bomba/hak/blueprint 0,3 s |
| Stały chwyt oburącz | Prawa na uchwycie, lewa pod lufą; przerwania i sprzątanie bez zmian |
| Brak znikania chwytu po ~0,1 s | Tylko Action–Action4 zawieszają pozę, Core nie jest akcją |
| Wyrzutnia nie przechodzi przez brzuch | Nowe pozy obu ramion z uwzględnieniem CAŁEGO modelu, w tym długiej tylnej rury |

Pomiar geometrii na modelu i rzeczywistych stawach: poprzednia prawa dłoń była przy X=0,15, Y=-0,20, Z=-0,70 względem UpperTorso; trzy bryły wyrzutni nachodziły na tułów. Po korekcie prawa dłoń X=1,05, Y=0,35, Z=-1,10, lufa skierowana po skosie (~45°), tył omija prawy bok tułowia. Lewa dłoń dopasowana ponownie. Sprawdzenie obróconych pudeł brył względem tułowia powiększonego o 0,1 studa z każdej strony: 0 nachodzeń dla nowej pozy. To pomiar geometrii, nie test animacji ani fizyki. Zmienione tylko sześć kątów pozy w Config.ItemEquip.HoldPoses.Rpg; mechanika i odrzut bez zmian. Budowa Rojo przeszła.

Play Kacpra: trzymanie widziane z boku i z przodu — tył lufy poza tułowiem, lewa dłoń przy wyrzutni; potem bieg i strzał. Ocena naturalności pozostaje otwarta.
