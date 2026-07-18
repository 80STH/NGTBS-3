// Generate entity sprites as 16x16 PNGs
const fs = require('fs');
const zlib = require('zlib');
const path = require('path');

const S = 16;
const OUT = path.join(__dirname, '..', '..', 'sprites');

if (!fs.existsSync(OUT)) fs.mkdirSync(OUT, { recursive: true });

// ── PNG encoder (reused from gen_icons) ──
function createPNG(pixels) {
    const raw = Buffer.alloc(S * (1 + S * 4));
    for (let y = 0; y < S; y++) {
        raw[y * (1 + S * 4)] = 0;
        for (let x = 0; x < S; x++) {
            const src = (y * S + x) * 4;
            const dst = y * (1 + S * 4) + 1 + x * 4;
            raw[dst] = pixels[src];
            raw[dst + 1] = pixels[src + 1];
            raw[dst + 2] = pixels[src + 2];
            raw[dst + 3] = pixels[src + 3];
        }
    }
    const compressed = zlib.deflateSync(raw);
    function crc32(buf) {
        let c;
        const table = [];
        for (let n = 0; n < 256; n++) {
            c = n;
            for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
            table[n] = c;
        }
        c = 0xFFFFFFFF;
        for (let i = 0; i < buf.length; i++) c = table[(c ^ buf[i]) & 0xFF] ^ (c >>> 8);
        return (c ^ 0xFFFFFFFF) >>> 0;
    }
    function chunk(type, data) {
        const len = Buffer.alloc(4);
        len.writeUInt32BE(data.length, 0);
        const typeAndData = Buffer.concat([Buffer.from(type, 'ascii'), data]);
        const crc = Buffer.alloc(4);
        crc.writeUInt32BE(crc32(typeAndData), 0);
        return Buffer.concat([len, typeAndData, crc]);
    }
    const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
    const ihdrData = Buffer.alloc(13);
    ihdrData.writeUInt32BE(S, 0);
    ihdrData.writeUInt32BE(S, 4);
    ihdrData[8] = 8; ihdrData[9] = 6;
    return Buffer.concat([sig, chunk('IHDR', ihdrData), chunk('IDAT', compressed), chunk('IEND', Buffer.alloc(0))]);
}

function blank() { return Buffer.alloc(S * S * 4); }

function sp(r,g,b,a) { return {r,g,b,a}; }
function set(buf,x,y,c) {
    if (x<0||x>=S||y<0||y>=S) return;
    const i = (y*S+x)*4;
    const sa = c.a/255, da = buf[i+3]/255, oa = sa+da*(1-sa);
    if (oa===0) { buf[i]=buf[i+1]=buf[i+2]=buf[i+3]=0; return; }
    buf[i]   = Math.round((c.r*sa + buf[i]*da*(1-sa))/oa);
    buf[i+1] = Math.round((c.g*sa + buf[i+1]*da*(1-sa))/oa);
    buf[i+2] = Math.round((c.b*sa + buf[i+2]*da*(1-sa))/oa);
    buf[i+3] = Math.round(oa*255);
}
function rect(buf,x,y,w,h,c) { for(let dy=0;dy<h;dy++) for(let dx=0;dx<w;dx++) set(buf,x+dx,y+dy,c); }
function circle(buf,cx,cy,r,c) { for(let dy=-r;dy<=r;dy++) for(let dx=-r;dx<=r;dx++) if(dx*dx+dy*dy<=r*r) set(buf,cx+dx,cy+dy,c); }
function tri(buf,x1,y1,x2,y2,x3,y3,c) {
    for(let y=0;y<S;y++) for(let x=0;x<S;x++) {
        const d1=(x-x1)*(y2-y1)-(y-y1)*(x2-x1);
        const d2=(x-x2)*(y3-y2)-(y-y2)*(x3-x2);
        const d3=(x-x3)*(y1-y3)-(y-y3)*(x1-x3);
        if((d1>=0&&d2>=0&&d3>=0)||(d1<=0&&d2<=0&&d3<=0)) set(buf,x,y,c);
    }
}

function save(name, buf) {
    fs.writeFileSync(path.join(OUT, name + '.png'), createPNG(buf));
    console.log('OK  ' + name);
}

// ── Buildings ──
const b = blank();
rect(b,1,4,14,10,sp(180,140,90,255));
tri(b,0,4,8,1,16,4,sp(153,64,38,255));
rect(b,6,10,4,4,sp(102,64,38,255));
rect(b,2,6,3,3,sp(217,230,255,255));
save('building_small', b);

const b2 = blank();
rect(b2,0,2,16,14,sp(128,140,153,255));
rect(b2,0,0,16,3,sp(102,115,128,255));
rect(b2,2,5,2,3,sp(204,217,255,255));
rect(b2,7,5,2,3,sp(204,217,255,255));
rect(b2,12,5,2,3,sp(204,217,255,255));
rect(b2,2,11,2,3,sp(204,217,255,255));
rect(b2,7,11,2,3,sp(204,217,255,255));
rect(b2,12,11,2,3,sp(204,217,255,255));
save('building_big', b2);

const tw = blank();
rect(tw,4,3,8,13,sp(140,128,115,255));
rect(tw,3,0,10,4,sp(140,128,115,255));
circle(tw,8,6,3,sp(255,179,0,255));
save('building_tower', tw);

const cv = blank();
rect(cv,1,5,14,6,sp(153,102,51,255));
rect(cv,1,3,14,3,sp(230,204,179,255));
circle(cv,3,13,2,sp(77,51,25,255));
circle(cv,13,13,2,sp(77,51,25,255));
save('building_caravan', cv);

const bp = blank();
rect(bp,0,3,16,10,sp(153,102,51,255));
rect(bp,1,3,3,13,sp(217,179,128,255));
rect(bp,12,3,3,13,sp(217,179,128,255));
rect(bp,5,5,6,3,sp(77,51,25,255));
save('building_blockpost', bp);

const tuE = blank();
rect(tuE,2,2,12,14,sp(77,51,25,255));
rect(tuE,2,2,2,14,sp(128,128,128,255));
rect(tuE,12,2,2,14,sp(128,128,128,255));
rect(tuE,5,4,6,8,sp(38,25,13,255));
tri(tuE,5,6,8,3,11,6,sp(0,255,0,255));
save('building_tunnel_entrance', tuE);

const tuX = blank();
rect(tuX,2,2,12,14,sp(77,51,25,255));
rect(tuX,2,2,2,14,sp(128,128,128,255));
rect(tuX,12,2,2,14,sp(128,128,128,255));
rect(tuX,5,4,6,8,sp(38,25,13,255));
tri(tuX,5,6,8,13,11,6,sp(255,0,0,255));
save('building_tunnel_exit', tuX);

const td = blank();
rect(td,3,5,2,3,sp(102,64,38,255));
rect(td,9,6,3,2,sp(128,128,128,255));
rect(td,5,3,3,4,sp(77,51,25,255));
rect(td,11,8,2,5,sp(153,102,51,255));
save('building_tunnel_destroyed', td);

const mh = blank();
rect(mh,1,7,14,9,sp(180,140,90,255));
rect(mh,2,9,2,3,sp(102,64,38,255));
rect(mh,2,6,3,3,sp(217,230,255,255));
tri(mh,0,7,8,2,16,7,sp(128,102,64,255));
rect(mh,0,8,16,2,sp(115,102,77,255));
save('building_mountain_house', mh);

const smh = blank();
rect(smh,2,9,12,7,sp(192,160,100,255));
rect(smh,3,10,3,3,sp(102,64,38,255));
tri(smh,0,9,8,3,16,9,sp(140,110,70,255));
save('building_small_mountain_house', smh);

const rmh = blank();
rect(rmh,4,3,3,5,sp(128,128,128,255));
rect(rmh,9,5,4,3,sp(102,64,38,255));
rect(rmh,1,10,6,6,sp(180,140,90,160));
rect(rmh,2,7,8,2,sp(115,102,77,160));
save('building_ruined_mountain_house', rmh);

const loco = blank();
rect(loco,1,2,14,12,sp(102,64,38,255));
rect(loco,4,3,8,5,sp(230,204,0,255));
rect(loco,2,12,12,2,sp(38,25,13,255));
circle(loco,4,15,1,sp(77,77,77,255));
circle(loco,12,15,1,sp(77,77,77,255));
save('locomotive', loco);

const tc = blank();
rect(tc,1,2,14,9,sp(179,38,38,255));
rect(tc,2,1,12,2,sp(153,102,51,255));
rect(tc,3,5,3,3,sp(217,230,255,255));
rect(tc,10,5,3,3,sp(217,230,255,255));
rect(tc,1,12,14,2,sp(38,25,13,255));
circle(tc,4,15,1,sp(77,77,77,255));
circle(tc,12,15,1,sp(77,77,77,255));
save('train_car', tc);

const ot = blank();
rect(ot,2,3,12,13,sp(77,51,25,255));
rect(ot,2,7,12,3,sp(255,102,0,255));
circle(ot,5,5,1,sp(230,204,0,255));
rect(ot,4,3,3,2,sp(0,0,0,255));
circle(ot,5,4,1,sp(230,204,0,255));
save('occupied_tunnel', ot);

// ── Obstacles ──
const sm = blank();
tri(sm,0,16,8,0,16,16,sp(115,102,77,255));
tri(sm,0,16,8,0,8,16,sp(140,128,115,255));
tri(sm,6,0,10,0,9,3,sp(242,242,255,255));
rect(sm,0,14,16,2,sp(77,64,51,255));
save('obstacle_super_mountain', sm);

const wm = blank();
tri(wm,0,16,8,0,16,16,sp(128,115,90,255));
tri(wm,0,16,8,0,8,16,sp(153,140,115,255));
rect(wm,0,14,16,2,sp(90,77,64,255));
save('obstacle_weak_mountain', wm);

const ms = blank();
tri(ms,0,16,12,2,16,16,sp(153,128,102,255));
tri(ms,0,16,12,2,12,16,sp(179,153,128,255));
rect(ms,0,14,16,2,sp(102,90,77,255));
save('obstacle_mountain_slope', ms);

const sms = blank();
tri(sms,0,16,13,0,16,16,sp(128,102,77,255));
tri(sms,0,16,13,0,13,16,sp(153,128,102,255));
tri(sms,11,0,15,0,14,4,sp(242,242,255,255));
rect(sms,0,14,16,2,sp(77,64,51,255));
save('obstacle_super_mountain_slope', sms);

const sr = blank();
rect(sr,1,2,14,14,sp(51,102,179,255));
for (let i=1;i<=3;i++) tri(sr,2,2,i*5,16,(i+1)*3,2,sp(77,128,204,255));
save('obstacle_sharp_reefs', sr);

// ── Fallback character circles ──
function unitCircle(name, r,g,b) {
    const buf = blank();
    circle(buf,8,8,7,sp(r,g,b,255));
    circle(buf,8,8,7,sp(Math.min(255,r+40),Math.min(255,g+40),Math.min(255,b+40),100));
    save(name, buf);
}
unitCircle('unit_warrior',   204,77,51);
unitCircle('unit_puncher',  51,204,77);
unitCircle('unit_rogue',    51,128,204);
unitCircle('unit_summoner', 204,51,204);
unitCircle('unit_divider',  230,179,26);
unitCircle('unit_summoned', 153,77,230);
unitCircle('unit_divided',  153,102,26);
unitCircle('unit_attack_test', 51,230,230);
unitCircle('unit_colossus', 230,140,26);
unitCircle('unit_keeper',   77,230,102);
unitCircle('unit_provoker', 230,51,77);
unitCircle('unit_zombie',   77,179,51);
unitCircle('unit_ghost',    179,77,255);
unitCircle('unit_lich',     204,51,204);
unitCircle('unit_power_lich', 38,13,51);

// Summoning Rod
const rod = blank();
rect(rod,5,2,6,12,sp(153,102,51,255));
circle(rod,8,3,3,sp(204,153,77,255));
save('unit_rod', rod);

console.log('\nDone! ' + (fs.readdirSync(OUT).length) + ' sprites generated.');
