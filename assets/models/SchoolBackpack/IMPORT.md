# Plecak szkolny — ESCAPE LAVA

Model według `docs/AKCESORIA_PROMPTY.md`, item 5. 788 trójkątów, 5 siatek, bez tekstur. Podgląd: preview.png. Edytowalny model: SchoolBackpack.blend. Import: SchoolBackpack.fbx.

| Część | RGB | Powierzchnie |
|---|---|---|
| Handle | 45,95,190 | korpus, klapa, szelki |
| Pocket | 32,72,155 | kieszenie, dolne pasy, uchwyt, wzmocnienia |
| Hardware | 195,200,208 | zamek, suwak, klamra, regulatory, etykieta |
| Bottle | 238,240,245 | butelka |
| BottleCap | 210,55,50 | zakrętka |

Wymiary są w studach. Korpus szerokości 1,26, od tyłu torsu +0,60 do +1,16; kieszeń do +1,30. Pełny model z szelkami ma większą głębokość niż sam plecak. Prawa butelka zwiększa szerokość do około 1,46.

Wszystkie siatki mają wspólny origin: BodyBackAttachment, czyli (0,-0.2,0.5) względem środka UpperTorso w Robloxie. Blender: X w prawo, -Y do tyłu postaci, Z w górę. Eksport FBX: -Z Forward / Y Up. Po imporcie sprawdź szerokość samego korpusu 1,26 studa; przeskaluj cały model razem, jeśli importer zastosował inne jednostki.

W Studio trzeba jeszcze opakować model w Accessory: Handle jako główna część, pozostałe 4 MeshParty połączone z nim sztywno przez WeldConstraint. Wszystkie części unanchored, Massless=true, CanCollide/CanTouch/CanQuery=false. Ustaw kolory z tabeli. Wewnątrz Handle utwórz prawdziwy Attachment nazwany BodyBackAttachment w punkcie wspólnego originu. Jeśli importer zachowa origin jako pivot, użyj tego pivotu; nie zakładaj, że geometryczny środek Handle jest punktem zaczepienia. Marker Empty w .blend jest wyłącznie referencją, FBX nie tworzy robloxowego Attachmentu.

Kontrola Blender: zamknięte siatki, zero krawędzi non-manifold i zerowych powierzchni; szczegóły validation.json. Obejrzano render. Dopasowanie w Studio i zachowanie przy chodzeniu/ragdollu pozostają do sprawdzenia: załóż z kamizelką, obróć ręce, sprawdź plecy i pozycję zaczepienia. Nie uruchamiano Roblox Studio.

## Dopasowanie R15 — poprawka
W .blend jest pełna referencja postaci: 14 pobranych siatek StarterCharacter gry oraz zastępcza głowa o zmierzonych wymiarach (oryginalna głowa zwraca HTTP 401). Referencja NIE jest eksportowana w FBX. Szelki rozstawiono na barkach, dolny pas poprowadzono wyżej po bokach, usuwając pętlę pod tułowiem. W pozycji stojącej: zero przecięć powierzchni z nogami; barkowe szelki nie przecinają tułowia ani głowy. Cienkie boczne pasy stykają się/przenikają miejscowo z ramionami i bokiem tułowia w ciasnej pozycji blokowej; animacje wymagają sprawdzenia w grze. Podglądy fit-front.png, fit-back.png, fit-side.png. Zachowano ten sam punkt zaczepienia; błędne wyrównanie do środka siatki zamiast BodyBackAttachment może nadal przesunąć całość w dół.
