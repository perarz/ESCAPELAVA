import bpy, bmesh, math, json, os
from mathutils import Vector
from mathutils.bvhtree import BVHTree

OUT = os.path.dirname(os.path.abspath(__file__))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.name = 'PumpkinHood'
sc.unit_settings.system = 'NONE'
asset = bpy.data.collections.new('Pumpkin_Export')
sc.collection.children.link(asset)
palette = {'Handle': (242, 113, 24), 'PumpkinShade': (205, 72, 17), 'FaceBlack': (25, 20, 32), 'Purple': (115, 49, 176)}
mats = {}
for name, rgb in palette.items():
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    c = tuple(v / 255 / 12.92 if v / 255 <= .04045 else ((v / 255 + .055) / 1.055) ** 2.4 for v in rgb) + (1,)
    m.diffuse_color = c
    m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = c
    m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = .82
    mats[name] = m

def mesh(name, verts, faces, material, collection=asset):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    collection.objects.link(ob)
    me.materials.append(mats[material])
    return ob

# HatAttachment is the origin. The head occupies Z -1.2 to 0.
# Squared inner profile clears the measured block head, including its corners.
N = 24
outer = [(-1.23, .78), (-.91, .93), (-.30, .95), (.13, .79), (.34, .31)]
inner = [(-1.23, .72), (-.91, .735), (-.30, .735), (.07, .72), (.14, .27)]
verts = []
for profile in (outer, inner):
    for z, r in profile:
        for j in range(N):
            a = j * math.tau / N
            x, y = math.sin(a), -math.cos(a)
            den = (abs(x) ** 6 + abs(y) ** 6) ** (1 / 6)
            ripple = (1 - .045 * (j % 2)) if profile is outer else 1
            verts.append((r * ripple * x / den, r * ripple * y / den, z))
faces, shade = [], []
M = len(outer)
# Closed front; the three actual face openings are cut below.
def visible(j, band):
    return True

for side in range(2):
    base = side * M * N
    for k in range(M - 1):
        for j in range(N):
            if not visible(j, k):
                continue
            q = (base + k*N+j, base + k*N+(j+1)%N, base + (k+1)*N+(j+1)%N, base + (k+1)*N+j)
            faces.append(q if side == 0 else tuple(reversed(q)))
            shade.append(side == 1 or j % 4 == 0)
    faces.append(tuple(base + (M-1)*N + j for j in range(N)))
    shade.append(side == 1)
# Stitch every open shell edge to its matching inner edge, including facial opening.
edge_count = {}
for f in faces:
    if min(f) >= M*N:
        continue
    for a, b in zip(f, f[1:] + f[:1]):
        key = tuple(sorted((a, b)))
        edge_count[key] = edge_count.get(key, 0) + 1
for (a, b), count in edge_count.items():
    if count == 1:
        faces.append((a, b, b+M*N, a+M*N))
        shade.append(True)
shell = mesh('Handle', verts, faces, 'Handle')
shell.data.materials.append(mats['PumpkinShade'])
for p, dark in zip(shell.data.polygons, shade):
    p.material_index = int(dark)

# True holes through the front wall only. Their silhouette evokes the classic smile.
bm=bmesh.new();bm.from_mesh(shell.data)
bmesh.ops.triangulate(bm,faces=list(bm.faces))
bm.to_mesh(shell.data);bm.free()
bpy.context.view_layer.update()
front_surface=BVHTree.FromObject(shell,bpy.context.evaluated_depsgraph_get())
def face_border(polygon):
    # Offset the outline outwards; the inner ring matches the actual aperture.
    p=[Vector(v) for v in polygon]; n=len(p)
    area=sum(p[i].x*p[(i+1)%n].y-p[(i+1)%n].x*p[i].y for i in range(n))
    sign=1 if area>0 else -1
    outer=[]
    for i in range(n):
        a=(p[i]-p[i-1]).normalized(); b=(p[(i+1)%n]-p[i]).normalized()
        na=Vector((a.y,-a.x))*sign; nb=Vector((b.y,-b.x))*sign
        bis=(na+nb).normalized()
        # Uneven carved/painted edge: broad asymmetric waves, not uniform trim.
        phase=i*math.tau/n
        seed=.8 if sum(q.x for q in p)<0 else 2.1
        width=.047+.014*math.sin(3*phase+seed)+.009*math.sin(5*phase+.4)
        outer.append(p[i]+bis*min(.085,width/max(.4,bis.dot(nb))))
    v=[]
    for i in range(n):
        for t in (0,.5):
            for ring in (p,outer):
                x,z=ring[i].lerp(ring[(i+1)%n],t)
                hit,_,_,_=front_surface.ray_cast(Vector((x,-2,z)),Vector((0,1,0)))
                assert hit is not None
                v.append((x,hit.y-.009,z))
    count=2*n
    mesh('IrregularBlackRim',v,[(2*i,2*i+1,2*((i+1)%count)+1,2*((i+1)%count)) for i in range(count)],'FaceBlack')
def cut_face(name, polygon):
    n=len(polygon)
    v=[(x,y,z) for y in (-1.4,-.64) for x,z in polygon]
    f=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    f += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    cutter=mesh(name,v,f,'PumpkinShade')
    bpy.context.view_layer.objects.active=shell
    mod=shell.modifiers.new(name,'BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter,do_unlink=True)
    # Front openings intentionally have no black rim (27.10 feedback).
for x in (-.255,.255):
    cut_face('Eye opening',[(x+.092*math.cos(i*math.tau/12),-.38+.145*math.sin(i*math.tau/12)) for i in range(12)])
upper=[(-.43+.86*i/12,-.66-.16*(1-((- .43+.86*i/12)/.43)**2)) for i in range(13)]
lower=[(-.43+.86*i/12,-.69-.27*(1-((- .43+.86*i/12)/.43)**2)) for i in range(12,-1,-1)]
cut_face('Smile opening',upper+lower)

# A squat bent purple stalk, wide enough to read on a phone.
stalk_verts = []
for x, y, z, r in [(0,0,.28,.145), (.02,0,.52,.12), (.17,.015,.68,.095), (.25,.015,.68,.08)]:
    for j in range(6):
        a=j*math.tau/6
        stalk_verts.append((x+r*math.cos(a), y+r*math.sin(a), z))
stalk_faces = [tuple(reversed(range(6))), tuple(range(18,24))]
for k in range(3):
    for j in range(6):
        stalk_faces.append((k*6+j,k*6+(j+1)%6,(k+1)*6+(j+1)%6,(k+1)*6+j))
mesh('PurpleStem', stalk_verts, stalk_faces, 'Purple')
mesh('PurpleLeaf', [(0,0,.36),(-.18,-.10,.44),(-.52,-.05,.41),(-.37,.13,.37),(-.16,.15,.39),(-.22,.02,.49)], [(0,1,5),(1,2,5),(2,3,5),(3,4,5),(4,0,5),(4,3,2,1,0)], 'Purple')

# A mischievous jack-o-lantern face on the back, the side seen by the player.
bpy.context.view_layer.update()
bvh = BVHTree.FromObject(shell, bpy.context.evaluated_depsgraph_get())
def applique(name, points):
    vs=[(x,2,z) for x,z in points]
    ob=mesh(name,vs,[tuple(range(len(vs)))],'FaceBlack')
    bm=bmesh.new();bm.from_mesh(ob.data)
    bmesh.ops.triangulate(bm,faces=list(bm.faces))
    bmesh.ops.subdivide_edges(bm,edges=list(bm.edges),cuts=2,use_grid_fill=True)
    for v in bm.verts:
        p,n,_,_=bvh.ray_cast(Vector((v.co.x,2,v.co.z)),Vector((0,-1,0)))
        assert p is not None
        v.co=p+Vector((0,.025,0))
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(ob.data);bm.free()
    bpy.context.view_layer.objects.active=ob
    mod=ob.modifiers.new('Inset thickness','SOLIDIFY'); mod.thickness=.035;mod.offset=-1
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return ob
applique('CrookedEyeLeft',[(-.58,-.33),(-.16,-.39),(-.29,-.12)])
applique('CrookedEyeRight',[(.16,-.39),(.58,-.27),(.34,-.11)])
applique('Nose',[(-.075,-.55),(.085,-.55),(.015,-.42)])
applique('ToothyGrin',[(-.58,-.68),(-.38,-.79),(-.31,-.70),(-.17,-.78),(-.04,-.69),(.09,-.78),(.23,-.68),(.35,-.75),(.56,-.61),(.42,-.95),(.26,-1.00),(.13,-.92),(-.01,-1.01),(-.17,-.93),(-.31,-.99),(-.47,-.90)])

# Split material regions so Roblox can recolor them as separate MeshParts.
bpy.ops.object.select_all(action='DESELECT')
shell.select_set(True);bpy.context.view_layer.objects.active=shell
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.separate(type='MATERIAL');bpy.ops.object.mode_set(mode='OBJECT')
for group in palette:
    objects=[o for o in asset.objects if o.type=='MESH' and o.data.polygons and o.data.materials[o.data.polygons[0].material_index].name==group]
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    if len(objects)>1:bpy.ops.object.join()
    objects[0].name=group
    objects[0]['ColorRGB']=list(palette[group])
handle=bpy.data.objects['Handle']
marker=bpy.data.objects.new('HatAttachment',None);asset.objects.link(marker);marker.parent=handle;marker.empty_display_size=.12
handle['RobloxAttachment']='HatAttachment'
handle['OriginRelativeToHead']='0, 0.6, 0'

# Use the existing measured R15 reference; preserve it only in the Blender file.
with bpy.data.libraries.load('/Users/kacper/escapelava/assets/models/SchoolBackpack/SchoolBackpack.blend',link=False) as (src,dst):
    dst.collections=[n for n in src.collections if n.startswith('R15_FitReference')]
ref=dst.collections[0];sc.collection.children.link(ref)
for o in ref.objects:
    o.location+=Vector((0,-.5,-2.1860168457))
ref.name='R15_REFERENCE_NOT_EXPORTED'

stage=bpy.data.collections.new('Preview');sc.collection.children.link(stage)
camera_data=bpy.data.cameras.new('Camera');camera=bpy.data.objects.new('Camera',camera_data);stage.objects.link(camera);sc.camera=camera
def aim(obj,point):obj.rotation_euler=(Vector(point)-obj.location).to_track_quat('-Z','Y').to_euler()
for name,loc,power in [('Key',(-3,-4,5),420),('Fill',(4,-1,2),200),('Rim',(0,4,3),330)]:
    d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='DISK';d.size=4
    o=bpy.data.objects.new(name,d);stage.objects.link(o);o.location=loc;aim(o,(0,0,-.6))
sc.world=bpy.data.worlds.new('World');sc.world.use_nodes=True
sc.world.node_tree.nodes['Background'].inputs[0].default_value=(.045,.032,.07,1)
sc.world.node_tree.nodes['Background'].inputs[1].default_value=.45
sc.render.engine='BLENDER_EEVEE';sc.render.resolution_x=1000;sc.render.resolution_y=1000;sc.render.resolution_percentage=100
sc.view_settings.view_transform='Standard';sc.render.image_settings.file_format='PNG'
camera_data.type='ORTHO';camera_data.ortho_scale=3.6
for name,loc in [('front',(2.8,-5,1.7)),('back',(-2.8,5,1.7))]:
    camera.location=loc;aim(camera,(0,0,-.60));sc.render.filepath=OUT+'/'+name+'.png';bpy.ops.render.render(write_still=True)
camera_data.ortho_scale=7.2;camera.location=(3,-6,1.6);aim(camera,(0,0,-2.1));sc.render.filepath=OUT+'/fit.png';bpy.ops.render.render(write_still=True)

bpy.ops.object.select_all(action='DESELECT')
stats={}
for o in asset.objects:
    if o.type!='MESH':continue
    o.select_set(True);o.data.calc_loop_triangles()
    stats[o.name]=len(o.data.loop_triangles)
bpy.context.view_layer.objects.active=handle
bpy.ops.export_scene.fbx(filepath=OUT+'/HalloweenPumpkin.fbx',use_selection=True,object_types={'MESH'},axis_forward='-Z',axis_up='Y',apply_unit_scale=True,apply_scale_options='FBX_SCALE_UNITS',bake_anim=False)
camera_data.ortho_scale=3.6;camera.location=(2.8,-5,1.7);aim(camera,(0,0,-.60))
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/HalloweenPumpkin.blend')
json.dump({'triangles':stats,'total':sum(stats.values()),'palette':palette,'attachment':'HatAttachment','origin_head':[0,.6,0]},open(OUT+'/model-info.json','w'),indent=2)
print('MODEL_RESULT',stats,sum(stats.values()))
