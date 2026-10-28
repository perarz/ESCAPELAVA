# Kontrakt Studio — nazwy i obiekty placu

Aktualizacja: **23.10.2026**. Kod i wybrane obiekty sprawdzone w **Edit**, bez Play. Stan zadań: [STATUS](STATUS.md). Zasady UI: [UI_RULES](UI_RULES.md). Historyczne wymiary/warianty/assety, kopie i przyczyny zmian: [archiwum kontraktu](archive/2026-10-23/STUDIO_CONTRACT.md); nie stosować starych nazw jako bieżącej specyfikacji.

**Kod = repo, mapa i GUI = plac.** Zmiany w StarterGui, ReplicatedFirst.LoadingGui, modelach, materiałach i scenach trzeba zapisać **Cmd+S**. Obecność w Edit nie potwierdza zapisu ani publikacji. Rojo build nie zawiera pełnego świata. Ustawienia zarządzane przez `default.project.json` zmieniać tam, bo sync nadpisuje Studio.

## Workspace i spawn

- `Workspace.Map` — geometria gry, obecnie budynki zagnieżdżone w `Map.Map.Map.Buildings`; kod szuka zgodnie z konfiguracją. Geometria konstrukcji zakotwiczona; bazę/obszary nieniszczalne chroni `Locked` / `Map.Locked`.
- `Workspace.SpawnPoints` — Folder, BasePart o dowolnych nazwach dla multi-spawnu. **23.10 ma 0 dzieci**; fallback: `Workspace.Map.Spawn` wyszukany przez PlayerService. Nie oznacza gotowej konfiguracji na 30–50 graczy. Kacper stawia punkty.
- `Workspace.Lobby.Spawn` — zakotwiczony BasePart, miejsce lobby. Lobby może zawierać zagnieżdżone dekoracje.
- `Workspace.Map.Locked.CashSpawns` — markery punktów cash; `ReplicatedStorage.Cash` to asset paczki. `Workspace.ItemSpawns` nie oznacza wdrożonego systemu wszystkich pickupów itemów.
- Rzeczy runtime: `ActiveBridges`, `ActiveCash`, `BlastDebris`, grupy kolapsu i lokalne FX — nie budować ich jako statycznej mapy.

## Budynki na destrukcji v4

W `Config.Structure.Buildings` jest **10 nazw**: OrangeBuilding, GreenBuilding, OrangeKebab, CyanOffice, OldBuilding2, PurpleSchool, OldBuilding1, Construction, PupleHotel, SandBuilding. Pisownia `PupleHotel` to rzeczywista nazwa kontraktu. Zmiana nazwy wymaga zmiany Config; bez dopasowania obiekt nie wejdzie w rejestr v4.

Konstrukcja to zawartość budynku poza `Decorations` i `Lights`. `StructKind` wymusza Slab/Beam/Wall/Column/Block/Trim/Other; `StructPermanent` chroni podporę; `StructNonStructural` oznacza listwę/ozdobę. `SID` nadaje bake, `StructMapRevision` jest atrybutem rewizji budynku. **Tag Pillar nie steruje kolapsem v4** (pozostał jako kategoria HP starszej destrukcji).

Po zmianie geometrii: `STRUCTURE_BAKE.luau` w Command Bar **Edit**, raport nietkniętego budynku (brak niezamierzonych spadających chunków), następnie zapis po zatwierdzeniu. TRYB 3 tworzy moduły `ServerStorage.StructureData.<BuildingId>` i SID na częściach. W Edit 23.10 brak zapisanych modułów. Runtime weryfikuje BakeVersion i GeometryHash, **nie MapRevision**; zapis zaokrągla liczby do 0,001. Zmiany reguł bake’u lub geometrii wymagają ponownej kontroli/zapisu; nie traktować samej rewizji jako zabezpieczenia.

Wszystko poza budynkami nadal może korzystać ze starszego passu podparcia. Nie usuwać go przed ustaleniem użytkowników. Panele ścian/stropów mogą być duże; kod przycina oryginał zamiast kasować grunt spod gracza. Union/Mesh nie traktować automatycznie jak ciętego boxa Part.

## Rekwizyty, auta, beczki i szkło

**26.10 — modele itemów bez Studs.** Decyzja dotyczy wyłącznie modeli Bomb, Blueprint, Bridge, HandHook, EnergyDrink, Rpg i C4 w ReplicatedStorage oraz sześciu modeli wystawy WeaponShopScene (C4 = StickyBomb). Wyczyszczono 156 przypisań wariantu na częściach itemów. Materiały bazowe, kolory, Neon i Glass pozostają. Mapa, lobby, pozostałe sceny, gotówka, postać, kopie zapasowe i UI zachowują poprzedni wygląd. Szersze usunięcie Studs zostało dokładnie cofnięte z historii Studio; narzędzia mapy nadal używają Studs. Potrzebny zapis placu **Cmd+S**.

- Całe meble: najwyższy Model pod folderem `Decorations`; także modele w folderach `Lamps` i `TrafficLights`. Samo słowo w nazwie Modelu nie zastępuje Folderu. `Props.MaxSize` i reguły wielkich dekoracji w Config/Destructible.
- `Props.Vaporize`: kategorie drobnicy znikają z obłokiem; inne meble są odrzucane/rozbijane. Nazwa folderu (także liczba pojedyncza/mnoga) jest kontraktem. **Barrels** obsługuje najpierw CarService — nie dopisywać aktualnych beczek jako zwykłych znikających rekwizytów.
- Auta: Model bezpośrednio w Folderze `Cars` (Config.Destruction.Cars.Folders). Party aut pozostają Locked, całością zarządza CarService; nie ciąć osobno ich karoserii.
- Beczki: Model bezpośrednio w Folderze `Barrels`; znany układ to 9 w Construction.Decorations.Barrels i 4 OutsideDecorations.Barrels. Mogą nie mieć Locked. Wybuch/ogień/profile i zapłon od F w CarService/PushService; fizyczny upadek beczki po utracie podparcia jest osobną ścieżką.
- Szyby: **Material = Glass**, bez wymaganego tagu. Skrypt naprawczy identyfikuje je po podpisie mapy: Transparency 0,60 i RGB 170/170/170, nie po rodzicu ani grubości. Historycznie 367 tafli (w tym 18 kurtynowych OrangeBuilding), stan liczbowy nie był przeliczany w tym audycie. Szkło aut/automatów/przystanku pomijane celowo, osobna decyzja.
- **Bulk-apply Plastic+Studs** na całej mapie usuwa Neon/Glass. Naprawy `LAMPS_LIGHTS`, `TRAFFIC_LIGHTS`, `WINDOWS_GLASS` szukają po rozmiarze/przezroczystości, nigdy po właściwości, którą naprawiają.
- Przechodnie drzwi/dekoracje mogą mieć `CanCollide=false`, ale muszą zachować `CanQuery=true`, żeby system podparcia je widział. Lokalny gruz przeciwnie: bez kolizji, dotyku i zapytań.

## Sklep-NPC i scena — stan 23.10

- `Workspace.Lobby.…WeaponsShop.NPC` — sprzedawca, rekurencyjne szukanie **przez WeaponsShop**, nie dowolny NPC. Party zakotwiczone. ShopService tworzy `ShopPrompt`, jeśli brak; prompt ma E, „Shop / Seller”, dystans 12. Zakup walidowany z serwera do 18 studów. ClothesShop.NPC to inny sprzedawca.
- `Workspace.WeaponShopScene` — osobna scena; gracz zostaje przy sprzedawcy, porusza się tylko kamera. `Decorations.<sceneModel>` to wystawa. W placu sześć modeli (Bomb, Blueprint, HandHook, EnergyDrink, Rpg, StickyBomb) i od 25.10 **sześć definicji**: `StickyBomb` to wystawa itemu **C4** (decyzja Kacpra 25.10: C4 = sticky bomb; nazwy modelu wystawy nie trzeba zmieniać).
- `ShopCameras` — markery pozycji, obecnie **nieużywane** (`UseCameraMarkers=false`). Dodanie markera haka nie jest zadaniem blokującym release. Po ewentualnym włączeniu parowanie po odległości, nazwy i obrót nie wyznaczają kierunku; markery anchored/niewidoczne/bez kolizji.
- Aktualne kadry automatyczne: bbox modelu, do wnętrza sceny, `AutoCameraYaw=20°`, `AutoCameraPitch=12°`, fill/minDistance w Config. Lista sortowana po położeniu na ścianie; otwarcie na pierwszym z lewej, nie po stałym shopOrder.
- **23.10:** scena/półki/podłoga/pokój broni wydłużone o 28 studów ku +Z; wystawa przesunięta +12: Rpg Z16, HandHook 24,8, StickyBomb 33,6, Blueprint 42,4, EnergyDrink 51,2, Bomb 60. To opis zapisanej w dokumentacji zmiany placu, nie nowa geometria generowana przez kod.
- **Najnowszy kod i odczyt Edit 23.10: stałe `WeaponShopScene.ShopLights`** — sześć `Light_<sceneModel>` (8 studów przed itemem, 5 wyżej, 1,5 w stronę kamery, celują w środek itemu) + `Light_EndStart` / `Light_EndFar` (ten sam odstęp 8,8 za skrajnymi itemami — szeroki kadr RPG miał ciemny brzeg ściany) — razem 8 SpotLightów: Angle 70, Brightness 3, Range 18, Shadows, ciepła biel RGB 255/242/225. Światła nie jadą z kamerą. Stary `ShopLight` i `Config.Shop.LightName` usunięte; ruchoma lampa miała opóźnione przeliczanie oświetlenia po przewinięciu. Dopasować testy do stałych lamp, nie przywracać starego kontraktu.
- `ShopController.closeShop(character?)` po respawnie przywraca CameraSubject nowemu Humanoidowi; poprawka 23.10 na kamerę zostającą w lobby przy starcie rundy z otwartym sklepem. Akceptacja Play otwarta.
- 23.10: na czas sklepu `Lighting.Ambient` u oglądającego = `Config.Shop.SceneAmbient` (po wyjściu wraca poprzednia wartość z `default.project.json`). Powód zmierzony: plam lamp Roblox nie rysuje na niskiej jakości grafiki, a „Automatic” startuje nisko. W sklepie ekwipunek niedostępny (`ShopController.isOpen` / `onOpenChanged` → InventoryController chowa przycisk).

## Modele w ReplicatedStorage

### COSMETICS — kontrakt dodany 26.10

**27.10 — uproszczenie COSMETICS na prośbę Kacpra:** usunięto Wallet, napis ESCAPE LAVA / THE CLOSET, zakładki i etykiety kategorii. Wszystkie produkty we wspólnym katalogu (garderoba nadal tylko posiadane). Sam licznik kasy po lewej, poniżej kontrolek Robloxa; główny tytuł wyśrodkowany. Kategorie wyposażenia i zapis pozostają bez zmian. Kopia UI: `ServerStorage.CosmeticsUI_v2_2710`; skrypt zmiany: `artifacts/cosmetics/simplify_ui.luau`. Build i kontrola Edit, bez testu Play. Wymagany Cmd+S.

**Aktualizacja po feedbacku 26.10: pełny ekran.** Małe okno zostało odrzucone. `Backdrop` ma nieprzezroczyste tło katalogu, `Root.Fit` liczy pełny viewport (wysokość referencyjna 1080, pion szerokość 800); root wypełnia ekran bez marginesu zewnętrznego. `Catalog.CategoryTabs` zawiera przyciski All/Head/Face/Torso/Back; stary FilterButton ukryty. Większe kafle mają CategoryWord, Orbit i Foot/ActionHint, a brakujące modele neutralny manekin + oznaczenie niedostępności. CloseButton to kopia `Inventory.Panel.Body.CloseButton` (86×86, Fredoka X, te same gradienty i obrysy). Kopia poprzedniego UI w `ServerStorage.CosmeticsUI_v1_2610`. Stan wyjściowy Cosmetics.Enabled=false, szablon ukryty, brak kart demonstracyjnych. Nie testowano Play ani telefonu.

Kacper zatwierdził osobny wyjątek: agent buduje UI COSMETICS w Studio. `StarterGui.Cosmetics` i `HUD.SideButtons.CosmeticsButton` postawione, ScreenGui wyłączone na start / ResetOnSpawn=false, napis `CosmeticsSign` nad ClothesShop.NPC. Przycisk COSMETICS y=130 pod Inventory; SettingsButton y=260. Pozostały wygląd paneli zachowany. **Cmd+S wymagany.**

- `Workspace.Lobby.…ClothesShop.NPC` — istniejący sprzedawca; serwer tworzy `CosmeticsPrompt` na jego korzeniu, aktywny tylko w LOBBY. Zakup wymaga bliskości właściwego NPC (parametry w Config.Cosmetics). Garderoba dostępna przyciskiem w całym lobby.
- `Workspace.ClothesShopScene.Decoriations.Platform.platform` — istniejąca platforma, rzeczywista pisownia. Jest obrócona, dlatego wysokość wyliczana z rzutu osi i rozmiaru. Opcjonalny `CosmeticsCamera` BasePart w scenie wyznacza kadr; bez niego kamera przed postacią, liczby w Config.
- `ReplicatedStorage.Cosmetics` — **27.10: HalloweenPumpkin gotowy jako Accessory; KevlarVest i SchoolBackpack nadal wymagają importu**. Wymagane Accessory `HalloweenPumpkin`, `KevlarVest`, `SchoolBackpack`. Folder nie ma placeholderów udających zaimportowane modele.
- Każdy produkt: BasePart/MeshPart `Handle` bezpośrednio w Accessory, z JEDNYM bezpośrednim Attachmentem odpowiedniej nazwy (toolbox ragdolla bierze pierwszy). Brak skryptów w assetach; Archivable=true dla Accessory, Handle, attachmentu i części. Helper montażu odtwarza sztywne weldy i wyłącza masę/kolizję/dotyk/zapytania. Nie obrabia geometrii ciała.

| ID | Cena | Punkt docelowy | Źródło do importu |
|---|---|---|---|
| HalloweenPumpkin | 500 | Head.HatAttachment | `assets/models/HalloweenPumpkin/HalloweenPumpkin.fbx` |
| KevlarVest | 750 | UpperTorso.BodyFrontAttachment | `assets/models/KevlarVest.fbx` |
| SchoolBackpack | 600 | UpperTorso.BodyBackAttachment | `assets/models/SchoolBackpack/SchoolBackpack.fbx` |

Punkty origin/kolory dyni i plecaka w ich plikach IMPORT.md; nie ustawiać attachmentów w geometrycznym środku Handle. **Kamizelka wymaga sprawdzenia originu/dopasowania po imporcie**. Nowe akcesoria nie dają HP ani bonusów. Dostępność modelu i attachmentów jest sprawdzana przed pobraniem gotówki.

Drzewo UI (wszystkie `*Shadow` mają ten sam rodzic co tekst; standard Fredoka):

```text
StarterGui.Cosmetics [ScreenGui, DisplayOrder 35, atrybut Design="shop_v4"]
  Backdrop [TextButton, pełny ekran, blokuje klikanie świata]
    Tone [UIGradient — ciemny fiolet → lawowy brąz u dołu], Studs [ImageLabel 6927295847, tylko w katalogu]
    (27.10: oba animuje kod w katalogu — Studs dostaje rozmiar ekranu + 1 kafel i płynie po skosie, Tone „oddycha” kolorem dołu i Offset; w placu zostają wartości spoczynkowe. Rozmiar kafla czytany z `Studs.TileSize`, liczby w `Config.Cosmetics.UI.Backdrop*`.)
  Root [Frame, center, NoHudScale=true]
    Fit [UIScale, wyłącznie skalowanie do ekranu]
    Body [Frame]
      Pop [UIScale, animacja wejścia]
      Header [Frame, przezroczysty], Title [TextLabel + Gold UIGradient], Status [TextLabel, do prawej]
      CloseButton [TextButton, Surface/Label/LabelShadow], Cash [klon HUD.Cash]
      Catalog [Frame]
        Empty [TextLabel] — bez filtrów kategorii (27.10)
        Items [ScrollingFrame, tylko pion, klony CardTemplate]
      Fitting [Frame]
        RarityTag [Frame] → Fill [Tint UIGradient], Label
        ItemName [TextLabel, TextScaled ≤84]
        PriceRow [Frame] → CashIcon [ImageLabel], Price [Tint UIGradient]
        NeedMore [TextLabel]
        ActionButton [TextButton, Surface (UIGradient + Shine), Label, Hover]
        BackButton [TextButton, Surface, Label, Hover], RotateArea, RotateHint
      Unlocked [Frame, Visible=false] → Pop [UIScale], Rays [Frame z belkami], Title [Gold], ItemName
  CardTemplate [Frame, Visible=false, NoHudScale=true]
    Card [TextButton, Outline 5 Round]
      Hover [UIScale], Fill [Frame, Gradient = kolor rzadkości]
      Art [Frame] → Rays [Frame z 8 belkami, UIAspectRatioConstraint]
      Preview [ViewportFrame — sam przedmiot]
      Foot [Frame, ciemny pas] → Square, Edge
      Rarity, ItemName [TextLabel], Unavailable [TextLabel]
      PriceRow [Frame, UIListLayout] → CashIcon, PriceText → Price [Tint UIGradient]
HUD.SideButtons.CosmeticsButton [TextButton, kopia stylistyki Inventory, fiolet]
```

**27.10 wieczór — sklep v4:** kolory kart, tagu i promieni ustawia kod z `Config.Cosmetics.UI.Rarities` według `CosmeticDefinitions.rarity`; kolory cen i przycisku z `Config.Cosmetics.UI.Colors` (gradient o nazwie `Tint` / `UIGradient` w `Surface`). Usunięte: `Fitting.ActionBar`, `Card.ActionHint`, `Header.Accent`, stare `Card.Price` i `Fitting.Price` bez wiersza z ikoną. Promienie to ostre belki zanikające na końcach, nigdy nie dochodzą do krawędzi karty (bez CanvasGroup). Kopia poprzedniej wersji: `ServerStorage.CosmeticsUI_v3_2710`; zapis budowy: `artifacts/cosmetics/shop_v4_ui.luau`. **Cmd+S wymagany.**

Desktop: trzy kolumny, większa dynia 2×2; pionowy ekran: dwie kolumny i wyższy panel. `Cosmetics` nie dodawać do `ScaledGuis`: własne skalowanie uwzględnia obie osie. Podglądy modeli są klonowane lokalnie, UI klonuje wyłącznie szablon postawiony w Studio. Przy braku importu etykieta COMING SOON, bez sprzedaży. Skrypt autorski `artifacts/cosmetics/build_ui.luau` jest tylko zapisem wykonanej budowy Edit; odmawia zastępowania istniejącego Cosmetics.

### Modele użytkowe

| Nazwa | Użycie / wymaganie |
|---|---|
| `Bomb` | Ręka i pocisk; Handle nośnikiem fizyki, kolizja pocisku na głównej kuli. |
| `Blueprint` | Tool planu mostu, mechaniką budowy steruje BridgeController. |
| `Bridge` | Model mostu i ghost; **bbox Edit 23.10 ~5,72×0,60×16,25**, nie dawne 13,25 długości. Wymiary czyta wspólnie ItemDefinitions.worldSize; zmieniać model, nie dwie kopie liczb. |
| `HandHook` | GrappleTool, model w ręce, nie lecący grot; największy part może być dyskiem Union, co nie przeszkadza jako bezmasowy uchwyt. |
| `EnergyDrink` | EnergyDrinkTool, wieczko po +X korpusu; obrót przez Config.EnergyDrink.GripRotation. |
| `Rpg` | Cała wyrzutnia, głowica **Cylinder** (`Config.Rpg.RocketPartName`); chwyt launcherGrip + HoldAlong/HoldBelow. Nie zmieniać nazwy głowicy bez Config. |
| `C4` | **25.10, skopiowany przez MCP (wymaga Cmd+S)**: kopia `WeaponShopScene.Decorations.StickyBomb` (Model, 8 partów, bbox 2,00×0,54×0,73). W ręce (Tool `C4Tool`, trzymany za środek bbox, obrót `Config.C4.GripRotation`) w locie i jako przyklejony ładunek (kod kładzie najcieńszą oś modelu na ścianę, liczy z rozmiaru — obrót modelu dowolny). Brak = C4 nie da się wyciągnąć (warn). |
| `Cash` | Paczka gotówki. |
| `StaminaBar` | BillboardGui-template, Enabled=false, ResetOnSpawn=false; `Root` → `Track` → `Fill`, `Root.Anim` UIScale, `Track.Border` UIStroke. Fill zakotwiczony dołem. Rozmiar w studach, padding/corner w skali, grubość Border liczy kod. |
| `PushAnimations.Push_TwoHands_R15` | KeyframeSequence do podglądu; **ID produkcyjne nieopublikowane (`0`)**. Sam model/sekwencja w ReplicatedStorage nie wystarcza na live. |

Narzędzia runtime: BombTool, BlueprintTool, GrappleTool, EnergyDrinkTool, RpgTool, C4Tool. Folder runtime `Workspace.ActiveCharges` (ładunki w locie i przyklejone) tworzy C4Service — nie stawiać go w placu. Modele wieloczęściowe spawane i pozycjonowane po środku bbox. Dla gestów potrzebne stawy Motor6D R15; brak stawów wyłącza kosmetykę, nie całą mechanikę.

## Rig, ragdoll i drabiny

`StarterPlayer.StarterCharacter` to ujednolicona baza R15 przekonwertowana na Motor6D; oryginalny Animate aktywny. Backup w ServerStorage nie jest aktywną postacią. Folder toolboxa `Workspace.Ragdoll Script, read the READ ME inside!` przenosi template `ragdoll` do StarterGui/PlayerGui; RagdollService musi wykonać to przed spawnem. Listener auto-unragdoll w toolboxie musi pozostać włączony. Nie przebudowywać rigu na podstawie dawnych instrukcji Rig Builder.

Tag `Ladder` na szynach/szczeblach (`LADDERS_TAG.luau`, Edit); nowa drabina wymaga tagowania. Klient tylko pomaga ją złapać, serwer traktuje przy niej ruch jak grunt w fall damage. Dawne DirectionalAnimations przeniesione do ServerStorage…Retired; nie publikować wycofanego zestawu chodu.

## Lawa — mechanika i aktualny wygląd

- `Workspace.Lava` **poza Map**. Kod zbiera wszystkie BasePart jako warstwy; nie wkładać tam lokalnego LavaWaveSurface ani ozdobnego nośnika.
- Odczyt Edit 23.10: `LavaSurface` 512,75×0,40×457, środek Y≈2,30, wierzch Y≈2,50, Transparency **0**, Basalt + **EscapeLava_RoundedRed_v4** (wariant, tile 56). `LavaMid` 512,75×0,60×457, środek Y≈1,45, Transparency 0, Neon. `LavaDeep` nie jest wymaganą warstwą.
- Part startuje z miejsca Kacpra; kod wymusza Locked/anchored i brak kolizji, dotyku, zapytań/cienia. Próg obrażeń i pływanie liczą fizyczną taflę; granice XZ z sumy warstw.
- Fizyczne falowanie Config.Lava.Wobble: wspólne 0,45, różnicowe 0,2 przycinane do szczelin. Nie podnosić amplitud bez kontroli styku warstw/przecięć i wpływu na próg obrażeń.
- Wizualna siatka klienta: 24×24 komórki, 625 wierzchołków, amplituda 1,05. Poza folderem Lava, bez kolizji. Śledzi atrybut **LavaVisualBaseY**, nie przejmuje fizycznego bujania; ukrywa obie oryginalne warstwy lokalnie, przy błędzie/wyłączeniu przywraca. `Workspace.LavaWavesDisabled=true` wyłącza podmianę. Brak uprawnień/budżetu EditableMesh ma pozostawić widoczną lawę.
- Ambient v5 (18.10) z pulą bąbli/dymu/świateł jest kliencki. Próg MinSurfaceY z histerezą dotyczy ambientu; **nie wyłącza fal w kanale**. `Texture` jest opcjonalne dla starego scrollu, nie wymagane do aktualnego materiału.
- Dawne nazwy Obsidian_v4b, Liquid_v6, Crust_v2/Contrast, LavaMacroFlow i LavaBloom w archiwum opisują eksperymenty. Istnienie wariantu w MaterialService nie oznacza, że jest na aktywnej tafli.

## Lighting i ustawienia projektu

Źródło prawdy: `default.project.json`. Obecnie Ambient RGB 88/58/52, OutdoorAmbient 129/91/68, ColorShift 70/70/70, Brightness 3, 16:42, ShadowSoftness 0, diffuse 0,965/specular 0,081, Exposure 0. Fog 192/192/192, start 0/koniec 100000. LightingStyle **Realistic**, GlobalShadows i PrioritizeLightingQuality true. ColorCorrection 0/0/0,4, tint 235/235/235; SunRays 0,2/0,6 (27.10: było 0,483/1 — Kacper: „żeby mniej raziło słońce”; słońce stoi nisko, ~18° nad horyzontem, więc często jest w kadrze); Blur Size 1 włączony. Atmosphere/Bloom nie są gałęziami projektu. Nie przywracać wrześniowego ShadowMap i grade’u z dawnych opisów jako „wartości finalnych”.

Sky/LightingPreset i gotowe lampy żyją w placu. Historycznie 36 kloszy ulicznych SurfaceLight na spodzie, 150 żarówek Neon bez dodatkowych PointLight; wnętrza: 52 oprawy, ciepły kolor 255/220/175, jasność zmniejszona o połowę, obudowy Plastic+Studs, klosze Neon. Ich backupy i narzędzia INTERIOR_LAMPS* opisane w archiwum. Liczb nie przeliczano w audycie 23.10. Zasięg lokalnego światła potrafi przenikać geometrię; strojenie zakresu nie zastępuje testu.

`Workspace.StreamingEnabled=false`, zoom 8–15, mouse lock off, kamera **Zoom** w projekcie. Ręczna zmiana zostanie nadpisana przez Rojo. Zmiana nowej gałęzi projektu może wymagać restartu Rojo; zgodność kodu sprawdzać z Source, nie require MCP.

## StarterGui — HUD i panele

Wymagane ScreenGui z **ResetOnSpawn=false**: HUD, Inventory, ShopUI, RoundTransition, RoundCountdown i EnergyVignette. HUD skaluje się z `Config.UI.ReferenceHeight=1200`, ScreenInsets=DeviceSafeInsets. Teksty/cienie/ramki: UI_RULES. Kod tylko podłącza logikę i animację do obiektów placu.

### HUD

- `HUD.Cash.Body`: Icon, CashLabel, CashLabelShadow, CashLabelShine, Pop UIScale; CashCounterController jedyny pisze kwotę. Aktualny zielony gradient „limonka” z 20.10, połysk tylko przy dolocie banknotu. Stary CoinLabel/CashDigits nie jest aktywnym licznikiem.
- Templates w HUD: CashFlyTemplate, CashFlashTemplate, CashRayTemplate, CashRingTemplate, CashTwinkleTemplate (Visible=false); kod klonuje istniejące wzory. CashPopup i CashSpark wycofane — nie tworzyć ich ponownie jako wymogu.
- `HUD.Hotbar.Slot1..3` **istnieją**; każdy Icon, ItemName, Count, Keybind, SelectStroke, Fill i UIScale animacji. Stałe pozycje bez UIListLayout, trzy sloty loadoutu; nowy item nie dodaje kolejnego slotu. Ramka czarna, wybrany biały.
- `HUD.RoundTimer.Title.State.StateLabel` i `HUD.RoundTimer.Timer.TimerLabel` (kontenery i cienie), Pop w Title/Timer, LineLeft/LineRight. Napisy GET READY podczas PREPARING/COUNTDOWN wróciły od 18.10; ROUND i ROUND OVER według aktualnego stanu.
- `HUD.KillMessage.Body`: Row (SkullLeft/Text/SkullRight) i Reward; KillLabel (+ cień), RewardLabel (+ cień), Pop. RichText tylko na tekście głównym. `HUD.WinMessage` podobny bez czaszek, WinLabel „YOU SURVIVED!”. Oba w Studio Visible=false, przezroczystości wzoru = stan widoczny. Kotwica KillMessage do oceny, nie poprawiona w ramach audytu.
- **`HUD.Detonator.DetonateButton`** (25.10, postawiony przez MCP na prośbę Kacpra, wygląd zaakceptowany przez Kacpra 25.10 na zrzucie z Edit — **wymaga Cmd+S**): `Detonator` = przezroczysty Frame 300×112, kotwica 1/0,5, pozycja {1,−24},{0,55,0} (prawa krawędź, trochę poniżej środka — nad przyciskiem skoku na telefonie), niesie `HudScale`. W nim `DetonateButton` = klon `SideButtons.InventoryButton` (kotwica 0,5/0,5, **Visible=false**): Fill z czerwonym gradientem 255/95/80 → 200/30/25 i studsami, Shine, `Label`/`LabelShadow` „DETONATE”, `SelectStroke` czarny 7, UIScale `Pop`. Znaczki z wzoru Badge: `Keybind` (lewy górny róg, ciemny, „G”, widoczny tylko z klawiaturą) i `Count` (prawy górny róg, żółty, 64×52, „x1”–„x3”); kod pisze w ich `Label`. Pokazuje go C4Controller, gdy gracz ma przyklejone ładunki w rundzie; klik = odpal wszystkie. Kod szuka `DetonateButton` w całym HUD — przeniesienie nic nie psuje, byle Pop był na przycisku, a HudScale na elemencie najwyżej w HUD. Brak = detonacja tylko klawiszem, warn w Output.
- `HUD.SideButtons.InventoryButton` z Badge/Pop, pokazuje się tylko w lobby. Panelu wyboru grafiki nie przywracać.
- **27.10: zębatka przeniesiona do `HUD.SettingsCorner.SettingsButton`** — prawy górny róg (`SettingsCorner` = przezroczysty Frame 56×56, kotwica 1/0, pozycja {1,−16},{0,4}, własny `HudScale`; rząd paska Robloxa, nad listą graczy). Przycisk wypełnia ramkę, `Gear.Size` = 0,65. Kod szuka zębatki po nazwie w całym HUD. Poniżej opis wyglądu z 26.10 (rozmiary sprzed przeniesienia).
- `HUD.Version` (27.10, **wymaga Cmd+S**): CanvasGroup 160×50 w prawym dolnym rogu (kotwica 1/1, {1,−16},{1,−8}), `GroupTransparency` 0,5 — cała etykieta z cieniem i obrysem półprzezroczysta naraz. W środku `VersionLabel` / `VersionLabelShadow` (Fredoka 34, obrys 3 Miter, cień −3/+3). Tekst wpisuje UIController: `"v" .. Config.UI.Version`.
- `HUD.SideButtons.SettingsButton` (26.10, postawiony przez MCP — **wymaga Cmd+S**): przycisk 112×112 pod INVENTORY (pozycja 0/130), przezroczysty — **bez żółtego kafelka** (Kacper 26.10), tylko UIScale `Pop` i `Gear` (UIScale `Size` 1,3, żeby wypełniała pole) zbudowana z kształtów, nie obrazka (UI_RULES 6): 4 zaokrąglone belki co 45° + koło, warstwy `Shadow*` (czarne, −4/+4), `Outline*` (czarne, +5) i `Fill*` (białe z gradientem pionowym — obrót gradientu kompensuje obrót belki), w środku `Hole` (ciemny, obrys 4). Widoczny zawsze.
- `HUD.CooldownBars.CooldownBarTemplate.Fill` dla pasków odnowienia; wzór w Studio, nie dynamiczne tworzenie pełnego GUI.
- **`HUD.Crosshair`** (24.10, celownik RPG, postawiony przez MCP w Edit — **wymaga Cmd+S**, wygląd zaakceptowany przez Kacpra 24.10 na zrzucie z Edit): Frame 64×64 px, AnchorPoint i Position 0,5/0,5, przezroczysty, **Visible=false** (włącza RpgController przy celowaniu PPM). W nim `Body` (cały rozmiar, kotwica 0,5) z UIScale **`Pop`** i cztery kreski `Top`/`Bottom`/`Left`/`Right`: białe 3×16 px, UIStroke czarny 1,5 Miter, przyklejone do krawędzi ramki — środek pusty, przerwa 16 px od środka. Kod czyta środek `Crosshair` jako punkt strzału (`ScreenPointToRay`), więc celownik musi zostać na środku ekranu. Brak = celowanie działa, strzał w środek ekranu, ostrzeżenie w Output.

### Ekwipunek

`StarterGui.Inventory` (ScreenGui, domyślnie zamknięty):

```text
Inventory
  Backdrop.Top / Bottom / Left / Right         TextButton, łapią klik bez zamykania
  Panel.Body                                  Pop UIScale, CloseButton
    Card.Header                               Title; 27.10: ostre rogi (UICorner 0) + własny UIStroke `Outline` 7 Miter,
                                              który zakrywa zaokrąglenie obrysu Card u góry; `Line` ukryta (dolny bok Outline ją zastępuje).
                                              Cofnięcie: UICorner 28, usunąć Outline, Line.Visible=true.
    Card.Shelf.Grid.ItemTemplate               niewidoczny wzór TextButton
      Fill / Shine / Icon / ItemName / Count / Price / SlotTag.Label / SelectStroke
      Fill.Pattern1 / Pattern2 / Sweep, Rim (UIStroke+UIGradient), Sparkles.Star1..4 (Twinkle)   23.10, bez Studs
    Card.Loadout                              Title, Status, Slot1 / Slot2 / Slot3
      SlotN.Icon / ItemName / Count / Keybind / Empty / SelectStroke / Pop
    Card.LavaPool.Band.Lava1                    pojedyncza ruchoma warstwa
  DetailsPanel.Body                           Pop UIScale, CloseButton
    Card.Header.ItemName / Count
    Card.Window                                Frame na model w świecie, nie ViewportFrame
    Card.Back                                  CanvasGroup, tło wokół okna
    Card.Price / Desc
    Card.Stats.Power / Range / Mobility         każda Bar.Fill
    Card.ActionButton                          Fill / Label / Shine / Hover
    Card.LavaPool.Band.Lava1
```

I / przycisk otwiera, I / X zamyka. Klik karty = DETAILS, ActionButton ADD/REMOVE/SWAP wybiera; drag i skróty 1–3 pozostają. Nie odtwarzać dawnego kontraktu OwnedList/LoadoutSlots z 30.09. Wzory, cienie i obrysy zachować przy przebudowie. ScreenPointToRay i ScreenGui.AbsolutePosition do przeliczenia pozycji okna/drag.

### Ustawienia

`StarterGui.Settings` (26.10, postawiony przez MCP — **wymaga Cmd+S**): ScreenGui ResetOnSpawn=false, Enabled=true, IgnoreGuiInset, DeviceSafeInsets, DisplayOrder 11 (nad ekwipunkiem), w `Config.UI.ScaledGuis`. Wygląd karty sklonowany z panelu sklepu.

```text
Settings.Panel                                 700×388 (27.10: +wiersz GRAPHICS), środek ekranu, Visible=false (otwiera zębatka)
  Body                                         UIScale Pop (wskok przy otwarciu)
    Card                                       ciemne tło + Studs, obrys 7, róg 28
      Header.Title / TitleShadow               „SETTINGS”
      CloseButton                              X na rogu, UIScale Hover
      Rows.Shoulder.Label / LabelShadow        „CAMERA SIDE”    + przyciski Left / Right
      Rows.CameraFx.Label / LabelShadow        „CAMERA TILT & FOV” + przyciski On / Off
      Rows.Graphics.Label / LabelShadow        „GRAPHICS”       + przyciski Low / High (27.10, klon wiersza CameraFx, Y 176)
```

Każdy przycisk wyboru (klon BUY: `Fill` z UIGradient, `Shine`, `Stroke`, `Label`/`LabelShadow`, UIScale `Hover`) ma atrybuty **`Setting`** (klucz z `Config.Settings.Options`) i **`Value`** (string albo bool). Kod koloruje `Fill`: wybrany zielony, reszta szara. Nazwy wierszy i przycisków są dowolne — kod szuka po atrybutach. Nowa opcja: wpis w Config + wiersz z przyciskami w Studio.

### Sklep

`StarterGui.ShopUI` (ResetOnSpawn=false, Enabled=false), zwarty dolny panel. **Wygląd z 25.10** (przebudowa przez MCP na prośbę Kacpra „kiczowate”, decyzje: węższy pasek, ciemne strzałki, cena osobno nad BUY, bez kasy w nagłówku). Kopia poprzedniej wersji: `ServerStorage.ShopUI_Backup_2510` — usunąć po akceptacji.

```text
ShopUI.Panel                                   800×300 px, dół-środek; jedyne dziecko ShopUI → jedna HudScale
  Header.ItemName / ItemNameShadow              żółty nagłówek ze studsami, bez kasy (kasa tylko w HUD)
  Description / DescriptionShadow               lewa kolumna, 410 px, 2 linie, wyrównanie do góry
  Stats.Power / Range / Mobility                każda Bar.Fill, pod opisem
  Price / PriceShadow                           prawa kolumna, duża zielona (62), nad przyciskiem
  BuyButton.Fill / Label / LabelShadow / Shine  280×84, napis 40 (mieści „NOT ENOUGH $”)
  StatusLabel / StatusLabelShadow               pod przyciskiem
  CloseButton.Label                             X na rogu
  PrevButton / NextButton                       84×84 PRZY bokach panelu (dzieci Panel, BEZ własnej HudScale);
                                                ciemne jak sloty paska: Fill czarny z gradientem przezroczystości, obrys 6
```

BUY zielony; NOT ENOUGH $ szary; feedback BOUGHT!/ADD IT IN INVENTORY. Kod szuka elementów po nazwie w całym `ShopUI`, więc przeniesienie strzałek do `Panel` niczego nie zmienia; `ShopCash` jest opcjonalny (brak = kasa tylko w HUD). Strzałki **nie mogą** wrócić jako osobne dzieci `ShopUI` z offsetem od środka — offset pozycji nie skaluje się z HudScale i rozjechałyby się z panelem. Kamera wraca do aktualnego Humanoida po zamknięciu/respawnie; sprawdzić w Play start rundy z otwartym panelem.

### Przejście i countdown

`StarterGui.RoundTransition.Curtain`: czarny pełnoekranowy prostokąt, domyślnie wyłączony; DisplayOrder 2147483000. `StarterGui.RoundCountdown.Digits`: ImageLabel 1/2/3, Pop UIScale, Fallback TextLabel/Fit; DisplayOrder 2147483001. Aktualne ID cyfr z korekty 18.10: 1=138070582477563, 2=111396101699867, 3=118607571016667. Kolory (`ImageColor3`, 26.10 żywsze): 3 = 255/55/45 czerwony, 2 = 255/230/30 (żółty bez bladego połysku — biel dawała blade złoto obrazka; 26.10 „trochę blady”), 1 = 50/255/80 zielony. Obrazki są same z siebie żółto-pomarańczowe, a kolor je tylko przyciemnia — zieleń potrzebuje małej składowej czerwonej, inaczej dół cyfry robi się oliwkowy. Rozmiar `Config.RoundTransition.CountdownScale` = 50% krótszego boku ekranu (było 63%), wskok 1,6× → 1× w 0,32 s. **Styl studsowych obrazków zostaje** (Kacper 26.10: zamiana na napisy z gradientem odrzucona). Wymaga zapisu placu, brak runtime budowania GUI.

### Winieta energy drinka

`StarterGui.EnergyVignette` domyślnie Enabled=false, IgnoreGuiInset, DisplayOrder −1. `Edges.Left/Right` (16% szerokości), `Top/Bottom` (20% wysokości), gradient do przezroczystego środka. MovementController zmienia tylko kolor/przezroczystość według Config. Złota, pulsująca, środek czysty; EnergyBolts wycofane.

## ReplicatedFirst — ekran ładowania v2

`ReplicatedFirst.LoadingGui` (nie „LoadingScreen”, bo to skrypt). `$ignoreUnknownInstances=true` w projekcie chroni GUI. Backdrop czarny; `Center` z HudScale → `Logo.Loading/LoadingShadow` („LOADING...”, szary) i `Title/TitleShadow` („ESCAPE LAVA”, żółty/pomarańczowy); `Bar.Fill.Studs`, Percent/PercentShadow i StatusLabel/StatusLabelShadow. **Montserrat Heavy** jest świadomym wyjątkiem fontu. Wypełnienie ciemnopomarańczowe ze studsami, puste tło bez studsów. Nazwy szczegółów porównać ze źródłem LoadingScreen przed przebudową. Kod klonuje istniejący wzór; brak modelu GUI nie jest naprawiany stworzeniem pełnego ekranu z kodu.

27.10 import complete: KevlarVest has VestShell renamed Handle, BodyFrontAttachment (0,-0.24,-0.5). SchoolBackpack rotated 180 degrees around Y before creating BodyBackAttachment. Each has 5 MeshParts and 4 welds, SmoothPlastic, Massless, no collision/touch/query. Originals in ServerStorage: KevlarVest_Imported_2710 and SchoolBackpack_Imported_2710. Vest RGB from FBX: Shell 22/22/25, Buckles 110/110/116, Patch 52/52/56, Straps 40/40/44, Trim 68/68/72. Earlier missing-import notes are historical.

27.10 fitting revision: full-screen scene, hidden catalog header and HUD while cosmetics is open (HUD restored on close), bottom purchase strip, BACK/X. TurnLeft/TurnRight removed; Fitting.RotateArea handles mouse/touch drag, global release and window focus cleanup. Camera framed from character bounds. Removed native rectangular GUI borders and card Orbit. Backup: ServerStorage.CosmeticsBeforeFitting_2710. Edit screenshot checked, source parse/sync and Rojo build passed; Play interaction not tested.

27.10 camera/strokes follow-up: CosmeticsPreview now removes runtime-only BaseParts before posing the rig, restores template PivotOffset and uses HumanoidRootPart as PrimaryPart. This prevents ragdoll helpers from distorting bounds; live camera result still needs confirmation. COSMETICS text strokes: black Miter, 5 for TextSize >=32, otherwise 3; button borders 4, ActionBar border 4. Source parse/sync and build passed; no Play test. Cmd+S required.

27.10 final fitting cleanup: CloseButton, ActionButton and BackButton now use transparent TextButton with SeparateLabel=true, child Surface (rounded border), Label and LabelShadow. Controller syncs button.Text to Label, preserving BUY/EQUIP updates. All COSMETICS border strokes Round; text strokes Miter. ActionBar inset 24, rounded 20, solid dark background. Two original Workspace.Part.SpotLights at approximately (54.25,129.18,-42.1) and (54.25,129.66,-28.1) are enabled and unchanged. Cosmetics no longer overrides Lighting.Ambient. Camera focus +0.04 of rig height, lift 1 stud, fitting height fraction 0.58.

27.10 cards: Card.Fill.Studs and Catalog.Footer/Shadow removed. Items needs 24px padding supplied by controller; card layout/canvas and row height account for it. Hover 1.015/gap28. CosmeticsSign: world offset (0,9,0), MaxDistance=300, AlwaysOnTop=true. Local fitting fill Attachment under preview HRP at (0,2,-4), PointLight brightness2/range16/no shadows/warm white, destroyed with preview. Original scene lights unchanged.

27.10 latest fitting contract: Body.Cash is a clone of HUD.Cash (WalletScale 0.55, no Glow/Shine), Cash.Body.CashLabel receives cosmetics cash with trailing $. Body.CloseButton hidden during fitting; Fitting.BackButton top-right returns to catalog. Plain Balance/Shadow removed. KevlarVest.Handle.BodyFrontAttachment Y=-0.0600009 (previously -0.2400009): worn vest lowered 0.18. Runtime FittingFill is now an Attachment under the scene platform, world position computed from initial preview base, outside rotating model; controller destroys it on replacement/exit. Preview removes all JointInstances and clears Bone.Transform. Backup CosmeticsBeforeWallet_2710.

27.10: Removed only the 200 front rim triangles from HalloweenPumpkin.FaceBlack; 456 rear-face triangles remain. Mesh baked into DataModel content via CreateDataModelContentAsync, applied to existing MeshPart with original size/CFrame. Four parts and HatAttachment preserved. Edit front view inspected, temporary preview removed. Backup: ServerStorage.HalloweenPumpkin_BeforeRimRemoval_2710. Cmd+S required; Play not tested. Local build.py no longer creates front rims; existing FBX/blend/previews are older and have NOT been regenerated.

27.10 CORRECTION after user report: the Studio EditableMesh rim edit was rejected as broken. Restored FaceBlack from HalloweenPumpkin_BeforeRimRemoval_2710 using original MeshId 99943081561875, original Size and CFrame. Do NOT reuse opaque DataModel mesh edit. Blender original opened and only front black rim vertices deleted; rear face remains 456 triangles. Saved HalloweenPumpkin_no-rims.blend and HalloweenPumpkin_no-rims.fbx, plus PumpkinBackFace.fbx (only changed mesh). front_no-rims.png rendered and inspected. Studio currently has ORIGINAL model with rims; corrected FBX NOT imported yet. CUA import blocked by ScreenCaptureKit error -3811 after initial timeout. Next: import corrected FBX through Studio, fit using same shared origin/attachment; do not blindly copy old FaceBlack Size because removing front geometry changes its bounding box. Verify front/back before replacing asset. Cmd+S remains unconfirmed.

27.10: Na prosbe Kacpra napis CosmeticsSign podniesiony 3x: StudsOffsetWorldSpace.Y z 9 do 27. Pozostale ustawienia zachowane. Odczyt Edit potwierdzony; Cmd+S wymagany.

27.10: Ostateczna wysokość CosmeticsSign.StudsOffsetWorldSpace.Y = 24 (zamiast 27), ustawiona i potwierdzona odczytem Edit. Cmd+S wymagany.
