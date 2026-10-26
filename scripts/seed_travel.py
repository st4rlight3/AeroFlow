"""Non-destructive fictional travel catalogue; all displayed business data lives in SQL Server.

The generator never overwrites existing products, inventory, prices or paid history.
Reruns fill missing demo identities only. Prices are teaching estimates in VND,
not quotes from real hotels, carriers or service providers.
"""
import argparse
from datetime import date,datetime,time,timedelta,timezone
from decimal import Decimal
import json
from pathlib import Path
import sys
from zoneinfo import ZoneInfo
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from app.db import connection
from scripts.international_catalog import AIRPORTS

CATEGORIES=(
 ('hotels','Khách sạn','hotel','NIGHT','phòng / đêm',2,1250000,14,22),
 ('activities','Vé tham quan','ticket','PERSON','người',1,480000,9,8),
 ('tours','Tour trong ngày','compass','PERSON','người',1,1450000,8,8),
 ('spa','Spa & thư giãn','spark','PERSON','người',1,650000,10,2),
 ('esim','eSIM du lịch','wifi','PERSON','gói',1,185000,7,1),
 ('buses','Vé xe khách','bus','PERSON','ghế',1,390000,7,6),
 ('transfers','Đưa đón sân bay','car','BOOKING','xe',3,590000,9,2),
 ('cars','Thuê xe','car','DAY','xe / ngày',4,1350000,9,24),
 ('cruises','Du thuyền','anchor','PERSON','người',1,3950000,9,30),
 ('trains','Vé tàu','train','PERSON','ghế',1,690000,8,5),
 ('visas','Dịch vụ visa','passport','PERSON','hồ sơ',1,2150000,9,1),
 ('events','Sự kiện & biểu diễn','music','PERSON','vé',1,890000,19,2),
)
DOMESTIC=(
 ('HAN','Hà Nội','VN','Việt Nam','ASIA','SE Asia Standard Time','Asia/Ho_Chi_Minh',21.028,105.834),
 ('SGN','TP. Hồ Chí Minh','VN','Việt Nam','ASIA','SE Asia Standard Time','Asia/Ho_Chi_Minh',10.776,106.701),
 ('DAD','Đà Nẵng','VN','Việt Nam','ASIA','SE Asia Standard Time','Asia/Ho_Chi_Minh',16.054,108.202),
)
DESTINATIONS=DOMESTIC+tuple(a for a in AIRPORTS if a[0] in ('SIN','BKK','DPS','ICN','NRT','CDG','SYD','JFK'))
TITLES={
 'hotels':('Aero Stay — nghỉ giữa lòng {}','Phòng sáng, khu vực tiếp khách riêng và bữa sáng theo gói. Nhận phòng từ 14:00, trả phòng trước 12:00.'),
 'activities':('City Pass — khám phá {}','Vé một ngày tại không gian trải nghiệm mô phỏng của AeroFlow. Gói nâng cấp kèm hoạt động hướng dẫn.'),
 'tours':('Một ngày dạo bước {}','Đi cùng hướng dẫn viên theo nhóm nhỏ. Lịch trình có thời gian nghỉ, bữa trưa và điểm hẹn rõ ràng.'),
 'spa':('Khoảng nghỉ tại {}','Liệu trình thư giãn 90 phút. Vui lòng đến sớm 15 phút và thông báo nhu cầu sức khỏe với nhân viên.'),
 'esim':('Kết nối khi đến {}','Gói dữ liệu 5 GB trong 7 ngày. Cần điện thoại hỗ trợ eSIM và không khóa mạng. Demo chỉ phát phiếu mô phỏng, không có kết nối viễn thông thật.'),
 'buses':('Xe du lịch {} — ngoại ô','Hành trình từ điểm hẹn trung tâm đến khu nghỉ ngoại ô. Có điều hòa, một kiện hành lý và ghế ngồi riêng.'),
 'transfers':('Từ sân bay về trung tâm {}','Xe riêng tối đa 3 khách cùng 2 kiện hành lý. Chờ 60 phút sau giờ đón đã chọn; ghi số chuyến bay ở phần ghi chú.'),
 'cars':('Tự lái khám phá {}','Xe số tự động 4 chỗ, nhận và trả tại cùng điểm hẹn. Giá chưa gồm nhiên liệu; cần giấy phép phù hợp. Mọi giấy tờ chỉ được kiểm tra trong kịch bản demo.'),
 'cruises':('Hải trình cuối tuần từ {}','Chuyến đi 2 ngày 1 đêm, cabin dùng chung theo gói. Điểm tập trung tại thành phố, có xe nối đến bến; không mặc định thành phố có cảng biển.'),
 'trains':('Chuyến tàu ngắm cảnh từ {}','Vé hành trình mô phỏng từ ga trung tâm đến vùng ngoại ô, ghế ngồi có điều hòa. Lịch khai thác mẫu của AeroFlow.'),
 'visas':('Chuẩn bị hồ sơ du lịch đến {}','Buổi tư vấn kiểm tra danh mục hồ sơ. Giá là phí hỗ trợ, không gồm lệ phí lãnh sự, không bảo đảm kết quả visa. Demo không nhận hộ chiếu hoặc tài liệu thật.'),
 'events':('Đêm nhạc và ánh sáng tại {}','Chương trình biểu diễn mô phỏng 2 giờ. Vé theo khu vực, không đánh số ghế; không phải vé của một sự kiện thương mại có thật.'),
}

def seed(start,days):
    counts=dict(destinations=0,products=0,packages=0,inventory=0)
    with connection() as conn:
        conn.timeout=180
        # Serialize imports with ordinary writes; do not add BEGIN TRAN under ODBC's transaction.
        conn.execute("DECLARE @r int; EXEC @r=sys.sp_getapplock @Resource=N'AeroFlow:travel:seed',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000; IF @r<0 THROW 52001,N'Seed busy.',1;")
        for order,(code,name,icon,*_) in enumerate(CATEGORIES):
            conn.execute('IF NOT EXISTS(SELECT 1 FROM dbo.TravelCategories WHERE Code=?) INSERT dbo.TravelCategories(Code,Name,Icon,SortOrder) VALUES(?,?,?,?)',code,code,name,icon,order)
        for code,name in [('wifi','Wi-Fi'),('breakfast','Bữa sáng theo gói'),('ac','Điều hòa'),('guide','Hướng dẫn viên'),('private','Dịch vụ riêng'),('luggage','Một kiện hành lý'),('qr','Phiếu QR'),('automatic','Xe số tự động')]:
            conn.execute('IF NOT EXISTS(SELECT 1 FROM dbo.TravelAmenities WHERE Code=?) INSERT dbo.TravelAmenities(Code,Name) VALUES(?,?)',code,code,name)
        provider=conn.execute("SELECT ProviderID FROM dbo.TravelProviders WHERE Name=N'AeroFlow Demo Experiences' AND IsDemo=1").fetchone()
        if not provider:provider=conn.execute("INSERT dbo.TravelProviders(Name,Description) OUTPUT INSERTED.ProviderID VALUES(N'AeroFlow Demo Experiences',N'Nhà cung cấp hư cấu dành cho đồ án. Không phát hành dịch vụ thật.')").fetchone()
        provider=provider[0]
        for di,a in enumerate(DESTINATIONS):
            code,city,country,cname,region,windows,iana,lat,lon=a
            image='/static/images/'+({'HAN':'hanoi.webp','SGN':'saigon.webp','DAD':'danang.webp'}.get(code,'destinations/'+code+'.svg'))
            slug='demo-'+code.lower()
            destination=conn.execute('SELECT DestinationID FROM dbo.TravelDestinations WHERE Slug=?',slug).fetchone()
            if not destination:
                destination=conn.execute('INSERT dbo.TravelDestinations(Slug,Name,CountryCode,CountryName,RegionCode,TimeZoneName,IanaTimeZone,Latitude,Longitude,ImagePath) OUTPUT INSERTED.DestinationID VALUES(?,?,?,?,?,?,?,?,?,?)',slug,city,country,cname,region,windows,iana,lat,lon,image).fetchone();counts['destinations']+=1
            for ci,(cat,name,icon,unit,label,guests,base,hour,duration) in enumerate(CATEGORIES):
                pslug=f'demo-{cat}-{code.lower()}'
                title,description=TITLES[cat];title=title.format(city)
                p=conn.execute('SELECT ProductID FROM dbo.TravelProducts WHERE Slug=?',pslug).fetchone()
                if not p:
                    p=conn.execute('INSERT dbo.TravelProducts(CategoryCode,DestinationID,ProviderID,Slug,Title,Summary,Description,Address,Latitude,Longitude,DurationMinutes,StarRating,FeaturesJson,IsPublished) OUTPUT INSERTED.ProductID VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,1)',
                      cat,destination[0],provider,pslug,title,description[:500],description+'\nNhà cung cấp: AeroFlow Demo Experiences. Toàn bộ tên gói, giá và lịch là dữ liệu mẫu phục vụ kiểm thử.',f'Điểm hẹn demo tại {city}; xem hướng dẫn trên phiếu',lat,lon,duration*60 if cat!='hotels' else 0,4 if cat=='hotels' else 0,json.dumps({'Language':'Tiếng Việt / English','Demo':True,**({'ValidityDays':7,'DataGB':5} if cat=='esim' else {}),'Includes':['Phí dịch vụ','Thuế theo giá niêm yết'],'Excludes':['Chi phí cá nhân'],'MeetingPoint':f'Điểm hẹn AeroFlow {city}'},ensure_ascii=False)).fetchone();counts['products']+=1
                    conn.execute('INSERT dbo.TravelProductImages(ProductID,ImagePath,Caption,SortOrder) VALUES(?,?,?,0)',p[0],image,'Minh họa '+city)
                conn.execute('EXEC dbo.sp_TravelLock ?',p[0])
                for amenity in {'hotels':['wifi','ac','breakfast'],'tours':['guide','qr'],'transfers':['private','ac','luggage'],'cars':['automatic','ac'],'buses':['ac','luggage'],'trains':['ac','luggage']}.get(cat,['qr']):
                    conn.execute('INSERT dbo.TravelProductAmenities(ProductID,AmenityID) SELECT ?,AmenityID FROM dbo.TravelAmenities a WHERE a.Code=? AND NOT EXISTS(SELECT 1 FROM dbo.TravelProductAmenities x WHERE x.ProductID=? AND x.AmenityID=a.AmenityID)',p[0],amenity,p[0])
                for tier in range(2):
                    pname=('Tiêu chuẩn','Linh hoạt')[tier]
                    pk=conn.execute('SELECT PackageID FROM dbo.TravelPackages WHERE ProductID=? AND Name=?',p[0],pname).fetchone()
                    if not pk:
                        pk=conn.execute('INSERT dbo.TravelPackages(ProductID,Name,Description,UnitCode,UnitLabel,MaxGuests,RefundPercent,CancelCutoffHours,ChangeAllowed,ChangeFee) OUTPUT INSERTED.PackageID VALUES(?,?,?,?,?,?,?,?,0,0)',p[0],pname,'Gồm thuế và phí. '+('Hoàn 50% trước hạn 48 giờ.' if tier==0 else 'Hoàn 100% trước hạn 24 giờ.'),unit,label,guests,50 if tier==0 else 100,48 if tier==0 else 24).fetchone();counts['packages']+=1
                    pending=[]
                    existing={r[0] for r in conn.execute("SELECT ServiceDate FROM dbo.TravelInventory WHERE PackageID=? AND SlotCode='DEFAULT' AND ServiceDate>=? AND ServiceDate<?",pk[0],start,start+timedelta(days=days))}
                    for offset in range(days):
                        day=start+timedelta(days=offset)
                        if day in existing:continue
                        local=datetime.combine(day,time(hour),ZoneInfo(iana))
                        finish=(datetime.combine(day+timedelta(days=1),time(12),ZoneInfo(iana)) if unit=='NIGHT' else local+timedelta(hours=duration))
                        price=Decimal(base+di*75000)*(Decimal('1.25') if tier else 1)*(Decimal('1.12') if day.weekday()>=5 else 1)
                        price=price.quantize(Decimal('1'))
                        pending.append((pk[0],day,'DEFAULT',local.astimezone(timezone.utc).replace(tzinfo=None),finish.astimezone(timezone.utc).replace(tzinfo=None),12 if unit in ('NIGHT','DAY','BOOKING') else 40,price))
                    if pending:
                        cur=conn.cursor();cur.fast_executemany=True;cur.executemany('INSERT dbo.TravelInventory(PackageID,ServiceDate,SlotCode,StartsAt,EndsAt,Capacity,UnitPrice) VALUES(?,?,?,?,?,?,?)',pending);counts['inventory']+=len(pending)
        conn.execute("IF NOT EXISTS(SELECT 1 FROM dbo.TravelCoupons WHERE Code='HELLOTRIP') INSERT dbo.TravelCoupons(Code,Title,Kind,Amount,MaxDiscount,MinSubtotal,UsageLimit,PerUserLimit,ValidFrom,ValidUntil) VALUES('HELLOTRIP',N'Giảm 10% cho chuyến đi mới','PERCENT',10,300000,500000,1000,2,'2026-10-01','2027-02-01')")
        articles=[('hanh-ly-gon','Chuẩn bị cho một chuyến đi nhẹ nhàng','Một danh sách ngắn giúp bạn bớt quên đồ.','Kiểm tra giấy tờ, thời gian nhận phòng và điều kiện hủy trước khi đi.\nMang theo một túi nhỏ cho đồ cần dùng trên đường.\nVới eSIM, kiểm tra khả năng hỗ trợ của điện thoại trước khi chọn gói.'),('doc-bao-gia','Đọc báo giá trước khi đặt','Giá theo đêm, theo người và theo xe khác nhau thế nào?','Khách sạn tính theo phòng và số đêm. Xe riêng tính theo xe; tour và vé tham quan thường tính theo người.\nAeroFlow hiển thị tổng tiền gồm thuế ở bước xác nhận.\nMỗi gói có hạn hủy và tỷ lệ hoàn riêng; điều kiện được lưu cùng đơn đặt.')]
        for slug,title,summary,content in articles:
            conn.execute('IF NOT EXISTS(SELECT 1 FROM dbo.TravelArticles WHERE Slug=?) INSERT dbo.TravelArticles(Slug,Title,Summary,Content,ImagePath) VALUES(?,?,?,?,?)',slug,slug,title,summary,content,'/static/images/aviation-hero.webp')
    return counts

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--apply',action='store_true');p.add_argument('--start-date',default='2026-12-01');p.add_argument('--days',type=int,default=62);a=p.parse_args()
    start=date.fromisoformat(a.start_date)
    if not 1<=a.days<=366:raise SystemExit('days must be 1..366')
    if not a.apply:print(json.dumps(dict(destinations=len(DESTINATIONS),products=len(DESTINATIONS)*len(CATEGORIES),packages=len(DESTINATIONS)*len(CATEGORIES)*2,inventory=len(DESTINATIONS)*len(CATEGORIES)*2*a.days,start=str(start),days=a.days)));return
    print(json.dumps(seed(start,a.days),ensure_ascii=False))

if __name__=='__main__':main()
