> ARCHIWUM sprzed audytu 23.10.2026. To zapis historyczny, nie bieżące instrukcje ani lista zadań. Aktualne dokumenty są dwa poziomy wyżej.

# UI_RULES.md — zasady robienia UI w ESCAPE LAVA

Reguły dla KAŻDEGO nowego elementu UI (HUD, panele, komunikaty, efekty). Zebrane z decyzji
Kacpra i pułapek z 10-11.10. Opisy konkretnych, już zbudowanych elementów (nazwy, rozmiary,
id obrazków) są w `docs/STUDIO_CONTRACT.md` → „UI z Figmy” — tu tylko zasady.

## Skąd brać wygląd
- **Projekt w Figmie**: https://www.figma.com/design/QT4JMeE6jssxdNPzJMmhNG/Untitled?node-id=0-1
  — czytać wtyczką Figma MCP: `get_metadata` strony `0:1` → skill `figma-design-to-code` →
  `get_design_context` węzła. Dokładne obrysy, cienie i efekty: `use_figma` (tylko odczyt),
  bo kod z `get_design_context` ich nie pokazuje.
- **Skala Figma → gra**: px Figmy × 2 (kasa, komunikat zabójstwa) albo × 2,5 (licznik czasu)
  — dobrać tak, żeby nowy element pasował do istniejących.
- **Kolor w Figmie ≠ ostatnie słowo**: Kacper ocenia w grze i zmienia (poświata licznika:
  biała w danych Figmy, czarna w grze). Zawsze pokazać zrzut i czekać na ocenę.

- **Panele: klasycznie, spójnie z HUD, czarny obrys na KAŻDEJ ramce** (19.10, po trzech wersjach
  ekwipunku). Kacper odrzucił: (1) ciemne półprzezroczyste karty bez charakteru („AI slop”),
  (2) i (3) udziwnienia — klocki z grubością, przekrzywione elementy, wytłoczone napisy, słupy nad
  lawą („gówno, bardziej klasycznie, brakuje strokeów”). Działa: układ jak w popularnych grach na
  Robloxie (nagłówek z tytułem, X na rogu, siatka kart, szczegóły obok, pasek na dole), motyw gry
  w teksturach (studsy `rbxassetid://6927295847`, lawa `rbxassetid://130840219862324`), a język
  wizualny z HUD: czarne obrysy, gradient licznika czasu, żółte liczniki, zielona kasa, sloty
  klonowane z paska. Wzór: `StarterGui.Inventory` (`STUDIO_CONTRACT` → „Ekwipunek”).

## Twarde zasady Kacpra
1. **Czcionka zawsze Fredoka** (`FredokaOne`). Jedyny wyjątek: ekran ładowania — **Montserrat Heavy** (decyzja Kacpra 20.10: „inny font, żeby było widać, że to loading screen”).
2. **UI to obiekty w Studio** (`StarterGui`) — buduję przez MCP, kod tylko podpina się pod
   nazwy i animuje. Wzory do klonowania (`*Template`) też w Studio, `Visible = false`.
3. **Pod każdym tekstem cień**: etykieta `<Nazwa>Shadow` obok `<Nazwa>` (ten sam rodzic),
   cała czarna, przesunięta w lewo i w dół (−3/+3 przy 50-76 px, −4/+4 przy 100 px), `ZIndex`
   niżej. Tekst i `Visible` kopiuje `TextShadowController` (z RichText — bez znaczników, gdy
   cień ma `RichText = false`).
4. **Obrys każdego tekstu**: `UIStroke` czarny, `LineJoinMode = Miter` (ostre narożniki), na
   tekście I na cieniu. Grubość: **5** przy dużych napisach (kasa, licznik, komunikaty),
   **3** przy małych (sloty). Jeden obrys dla całego HUD — rozjazd od razu widać.
5. **Zawsze skalowalne**: px projektu przy wysokości ekranu 1200, kotwica do najbliższej
   krawędzi, `HudScaleController` dokłada każdemu dziecku `HUD` skalę z wysokości ekranu.
   `HUD.ScreenInsets = DeviceSafeInsets` — góra ekranu jest nasza (pasek Robloxa siedzi
   tylko w lewym rogu).
6. **Ostre w każdej skali**: tekst, ramki i zaokrąglenia rysuje Roblox. Obrazki tylko tam,
   gdzie nie da się kształtem, w rozdzielczości ≈ największego wyświetlanego rozmiaru (ikony
   512 px). Obrazek wielokrotnie większy niż na ekranie też się rozmywa (kreska licznika
   1024 px → ~80 px była „shitty”; 260 px jest ostra).
7. **Bez rozmytych poświat za tekstem** — Kacper je usunął; UI Robloxa nie ma prawdziwego
   rozmycia, a obrazek-poświata wygląda jak smuga.
8. **Efekty tam, gdzie gracz patrzy** — na środku ekranu, nie w rogu („nikt nie patrzy w róg
   podczas gry”). Bez czarnych obrysów na drobnych cząsteczkach (wyglądają jak czarne odłamki).

## Pułapki silnika (każda kosztowała podejście)
- **`AutomaticSize` + dziecko z rozmiarem w skali rodzica = pętla** (napis rozpychał się do 2×
  i przestawał reagować na tekst). W kontenerze `AutomaticSize` trzymać tylko rzeczy z
  rozmiarem w px albo samymi `AutomaticSize`; poświaty/tła o stałym rozmiarze — obok.
- **`UIListLayout` trzyma pozycję** — elementu w layoucie nie da się animować przesunięciem.
  Jeśli coś ma podskakiwać (sloty paska), stałe pozycje zamiast layoutu.
- **`TextWrapped = false` wyłącza `TextScaled`**, a `TextScaled` ma sufit 100 px. Duże napisy
  = stała `TextSize` (skaluje je HudScale), małe w polach = `TextScaled`.
- **`UIGradient` przezroczystości na obiekcie z `UIStroke` zjada ramkę** — tło/gradient jako
  osobne dziecko (`Fill`).
- **Jeden `UIGradient` = jedna rola**: kolor napisu i przesuwany połysk się gryzą — połysk
  jako osobna nakładka (`CashLabelShine`).
- **`UIStroke.Thickness` jest w pikselach** — w `BillboardGui` z rozmiarem w studach liczyć ją
  w kodzie z rozmiaru (pasek staminy), padding w skali.
- **`UIScale` skaluje wokół `AnchorPoint`** — element, który ma „wskakiwać” ze środka,
  potrzebuje kotwicy 0,5/0,5.
- **Dwa układy współrzędnych (19.10, ekwipunek: w Edit dobrze, w Play wszystko wyżej o pasek
  Robloxa)**: `AbsolutePosition` i `InputObject.Position` liczą od miejsca POD paskiem, a GUI z
  `IgnoreGuiInset` / `DeviceSafeInsets` ustawia dzieci od górnego brzegu ekranu. Pozycja w takim
  GUI = punkt − `ScreenGui.AbsolutePosition` (zapas: + `GuiService:GetGuiInset()`), promień kamery
  z punktu GUI = `Camera:ScreenPointToRay` (NIE `ViewportPointToRay`). W Edit pasek ma 0 px —
  podgląd tego nie złapie.
- **Słabe tabele (`__mode = "k"`) z Instance jako kluczem gubią wpisy** — stan UI trzymać w
  zwykłych tabelach (ramka slotu nie znikała, połysk stawał).

## Animacje (wzorzec)
- Wskok = `UIScale` o nazwie `Pop` postawiony w Studio; kod: skala → 1 z `Back`/`Elastic`.
- Liczby w `Config` (`Config.UI.*`, `Config.Cash.Fly`), nie w kodzie.
- Wszystko, co klonuje kod, idzie do JEDNEGO kontenera na efekt i jest sprzątane w całości.
- Kolejny event w trakcie animacji: żeton / `Cancel` poprzednich tweenów — nic nie może
  „dokończyć się” na nowym stanie.

## Proces
1. Przeczytać węzeł z Figmy (wymiary, kolory, obrysy, efekty).
2. Zbudować w Studio przez MCP, zrobić zrzut (`screen_capture`) i porównać z Figmą.
3. Kod tylko logika + animacje; po zmianie kodu sprawdzić sumę kontrolną Studio vs dysk.
4. Dopisać element do `STUDIO_CONTRACT.md` → „UI z Figmy”, test do `TESTY.md`.
5. Przypomnieć Kacprowi o Cmd+S — UI żyje w placu, nie w gicie.
