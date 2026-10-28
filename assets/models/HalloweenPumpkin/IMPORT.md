# Halloween — dyniowy kaptur

Zabawna dynia z zamkniętym przodem i trzema prawdziwymi otworami: owalne oczy oraz uśmiech w stylu klasycznej twarzy Robloxa. Z tyłu pozostaje halloweenowa mina widoczna dla kamery gracza. 1502 trójkąty, cztery części kolorystyczne, bez tekstur.

| MeshPart | RGB | Znaczenie |
|---|---|---|
| Handle | 242,113,24 | pomarańczowa skorupa |
| PumpkinShade | 205,72,17 | żebra, wnętrze i krawędzie |
| FaceBlack | 25,20,32 | oczy, nos i zębaty uśmiech z tyłu oraz grubsze, nieregularne obramowania otworów z przodu |
| Purple | 115,49,176 | krzywy ogonek i liść |

Wspólny origin wszystkich części: HatAttachment, (0,0.6,0) względem środka głowy Roblox. Blender: origin (0,0,0), środek głowy (0,0,-0.6), przód -Y, góra Z. Eksport -Z Forward / Y Up. Model około 1,9 studa szerokości, 1,91 wysokości z ogonkiem. Nie skaluj każdej części osobno.

Importuj HalloweenPumpkin.fbx jako osobne siatki. Ustaw wskazane kolory, opakuj w Accessory, nazwij główną część Handle, połącz pozostałe z Handle przez WeldConstraint. Wszystkie MeshParty: unanchored, Massless=true, CanCollide/CanTouch/CanQuery=false. W Handle utwórz prawdziwy HatAttachment w punkcie wspólnego originu; Empty z Blendera jest tylko znacznikiem i nie jest robloxowym Attachmentem. Nie umieszczaj attachmentu automatycznie w geometrycznym środku skorupy.

Plik .blend zawiera referencję R15 z gry (14 pobranych siatek i zastępcza głowa o zmierzonych wymiarach). Referencja i światła nie są eksportowane do FBX. Podglądy: front.png, back.png, fit.png. Dopasowanie sprawdzono wizualnie na nieruchomej postaci; ruch głowy, animacje i ragdoll trzeba sprawdzić w Studio. Inne nakrycia głowy, w szczególności nauszniki, nie były dopasowywane do tego modelu.

27.10: Removed only the 200 front rim triangles from HalloweenPumpkin.FaceBlack; 456 rear-face triangles remain. Mesh baked into DataModel content via CreateDataModelContentAsync, applied to existing MeshPart with original size/CFrame. Four parts and HatAttachment preserved. Edit front view inspected, temporary preview removed. Backup: ServerStorage.HalloweenPumpkin_BeforeRimRemoval_2710. Cmd+S required; Play not tested. Local build.py no longer creates front rims; existing FBX/blend/previews are older and have NOT been regenerated.

27.10 CORRECTION after user report: the Studio EditableMesh rim edit was rejected as broken. Restored FaceBlack from HalloweenPumpkin_BeforeRimRemoval_2710 using original MeshId 99943081561875, original Size and CFrame. Do NOT reuse opaque DataModel mesh edit. Blender original opened and only front black rim vertices deleted; rear face remains 456 triangles. Saved HalloweenPumpkin_no-rims.blend and HalloweenPumpkin_no-rims.fbx, plus PumpkinBackFace.fbx (only changed mesh). front_no-rims.png rendered and inspected. Studio currently has ORIGINAL model with rims; corrected FBX NOT imported yet. CUA import blocked by ScreenCaptureKit error -3811 after initial timeout. Next: import corrected FBX through Studio, fit using same shared origin/attachment; do not blindly copy old FaceBlack Size because removing front geometry changes its bounding box. Verify front/back before replacing asset. Cmd+S remains unconfirmed.
