//
//  ViewController.swift
//  IndoorLocationByBeacon
//
//  Created by Moosung Gil on 2016. 10. 5..
//  Copyright © 2016년 Moosung Gil. All rights reserved.
//

import UIKit
import CoreLocation
import FirebaseDatabase

class ViewController: UIViewController, CLLocationManagerDelegate {
    
    var locationManager: CLLocationManager!
    var ref: FIRDatabaseReference!
    var beaconInfoDict: [String : AnyObject]!
    var beaconUUID: String!
    var beaconIdentifier: String!
    
    @IBOutlet var xValue:UILabel!
    @IBOutlet var yValue:UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        self.ref = FIRDatabase.database().reference()
        
        ref.observe(.value, with: { snapshot in
            let dict = snapshot.value as! [String : AnyObject]
            let sceneDict = dict["260"] as! [String : AnyObject]
            self.beaconInfoDict = sceneDict["beacons"] as! [String : AnyObject]
            
            for (macAddr, obj) in self.beaconInfoDict {
                if self.beaconUUID == nil {
                    self.beaconUUID = (obj as! [String : AnyObject])["uuid"] as! String
                }
                
                if self.beaconIdentifier == nil {
                    self.beaconIdentifier = (obj as! [String : AnyObject])["identifier"] as! String
                }
                
            }
            
            if self.beaconUUID != nil && self.beaconIdentifier != nil {
                self.locationManager = CLLocationManager()
                self.locationManager.delegate = self
                self.locationManager.requestWhenInUseAuthorization()
            }
        })
        
        
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse {
            if CLLocationManager.isMonitoringAvailable(for: CLBeaconRegion.self) {
                if CLLocationManager.isRangingAvailable() {
                    startScanning()
                }
            }
        }
    }
    
    func startScanning() {
        let uuid = UUID(uuidString: self.beaconUUID)!
        let beaconRegion = CLBeaconRegion(proximityUUID: uuid, identifier: self.beaconIdentifier)
        
        locationManager.startMonitoring(for: beaconRegion)
        locationManager.startRangingBeacons(in: beaconRegion)
    }
    
    func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
        let knownBeacons = beacons.filter{ $0.proximity != CLProximity.unknown }.sorted { $0.accuracy < $1.accuracy}
        
        
        if knownBeacons.count > 0 {
            if knownBeacons.count >= 3 {
                var points:[Point] = []
                
                for i in 0 ..< knownBeacons.count {
                    if i > 3 {
                        break
                    }
                    
                    let beacon = knownBeacons[i]
                    let beaconInfo:[String:AnyObject] = getBeaconInfo(beacon.proximityUUID.uuidString, major: Int(beacon.major), minor: Int(beacon.minor))
                    if beaconInfo.isEmpty {
                        continue
                    }
                    
                    print("major : \(beacon.major), accuracy : \(beacon.accuracy), rssi : \(beacon.rssi)")
                    
                    let left = beaconInfo["left"] as! Double
                    let top = beaconInfo["top"] as! Double
                    let zPos = beaconInfo["zPos"] as! Double
                    
                    
                    points.append(Point(position: (xCoord: left.divided(by: 100), yCoord: top.divided(by: 100), zCoord: zPos.divided(by: 100)), distance: beacon.accuracy))
                }
                
                if points.count < 3 {
                    return
                }
                
                let position = trilateration(point1: points[0], point2: points[1], point3: points[2])
                
                xValue.text = String(position[0])
                yValue.text = String(position[1])
                
//                print("x : \(position[0]), y : \(position[1])")
                
            }
            
            updateDistance(knownBeacons[0].proximity)
        } else {
            updateDistance(.unknown)
        }
    }
    
    func trilateration(point1: Point, point2: Point, point3: Point) -> [Double] {
        
        let x1 = point1.position.xCoord
        let y1 = point1.position.yCoord
        
        let x2 = point2.position.xCoord
        let y2 = point2.position.yCoord
        
        let x3 = point3.position.xCoord
        let y3 = point3.position.yCoord
        
        
        var P1 = [x1, y1]
        var P2 = [x2, y2]
        var P3 = [x3, y3]
        
        if let z1 = point1.position.zCoord {
            P1.append(z1)
        }
        
        if let z2 = point2.position.zCoord {
            P2.append(z2)
        }
        
        if let z3 = point3.position.zCoord {
            P3.append(z3)
        }
        let distA:Double = point1.distance
        let distB:Double = point2.distance
        let distC:Double = point3.distance
        
        var ex: [Double] = []
        var tmp: Double = 0
        var P3P1: [Double] = []
        var ival: Double = 0
        var ey: [Double] = []
        var P3P1i: Double = 0
        var ez: [Double] = []
        var ezx: Double = 0
        var ezy: Double = 0
        var ezz: Double = 0
        
        // ex = (P2 - P1)/||P2-P1||
        for i in 0 ..< P1.count {
            let t1 = P2[i]
            let t2 = P1[i]
            let t:Double = t1-t2
            tmp += (t*t)
        }
        
        for i in 0 ..< P1.count {
            let t1 = P2[i]
            let t2 = P1[i]
            let exx: Double = (t1-t2)/sqrt(tmp)
            ex.append(exx)
        }
        
        // i = ex(P3 - P1)
        for i in  0 ..< P3.count {
            let t1 = P3[i]
            let t2 = P1[i]
            let t3 = t1-t2
            P3P1.append(t3)
        }
        
        for i in 0 ..< ex.count {
            let t1 = ex[i]
            let t2 = P3P1[i]
            ival += (t1*t2)
        }
        //ey = (P3 - P1 - i · ex) / ‖P3 - P1 - i · ex‖
        for i in 0 ..< P3.count {
            let t1 = P3[i]
            let t2 = P1[i]
            let t3 = ex[i] * ival
            let t = t1 - t2 - t3
            P3P1i += (t*t)
        }
        
        
        for i in 0 ..< P3.count {
            let t1 = P3[i]
            let t2 = P1[i]
            let t3 = ex[i] * ival
            let eyy = (t1 - t2 - t3)/sqrt(P3P1i)
            ey.append(eyy)
        }
        
        if P1.count == 3 {
            ezx = ex[1]*ey[2] - ex[2]*ey[1]
            ezy = ex[2]*ey[0] - ex[0]*ey[2]
            ezz = ex[0]*ey[1] - ex[1]*ey[0]
        }
        
        ez.append(ezx)
        ez.append(ezy)
        ez.append(ezz)
        
        //d = ‖P2 - P1‖
        let d:Double = sqrt(tmp)
        var j:Double = 0
        
        //j = ey(P3 - P1)
        for i in 0 ..< ey.count {
            let t1 = ey[i]
            let t2 = P3P1[i]
            j += (t1*t2)
        }
        //x = (r12 - r22 + d2) / 2d
        let x = (pow(distA,2) - pow(distB,2) + pow(d,2))/(2*d)
        //y = (r12 - r32 + i2 + j2) / 2j - ix / j
        let y = ((pow(distA,2) - pow(distC,2) + pow(ival,2) + pow(j,2))/(2*j)) - ((ival/j)*x)
        
        var z: Double = 0
        
        if P1.count == 3 {
            z = sqrt(pow(distA,2) - pow(x,2) - pow(y,2))
        }
        
        var unknowPoint:[Double] = []
        
        for i in 0 ..< P1.count {
            let t1 = P1[i]
            let t2 = ex[i] * x
            let t3 = ey[i] * y
            let t4 = ez[i] * z
            let unknownPointCoord = t1 + t2 + t3 + t4
            unknowPoint.append(unknownPointCoord)
        }
        
        return unknowPoint
        
    }
    
    func getBeaconInfo(_ uuid:String, major:Int, minor:Int) -> [String: AnyObject] {
        
        var beaconInfo:[String:AnyObject] = [:]
        
        for (macAddr, info) in beaconInfoDict {
            if uuid != info["uuid"] as! String {
                continue
            }
            
            if major != info["major"] as! Int {
                continue
            }
            
            if minor != info["minor"] as! Int {
                continue
            }
            
            beaconInfo = info as! [String : AnyObject]
        }
        
        return beaconInfo
        
        
    }
    
    func updateDistance(_ distance: CLProximity) {
        UIView.animate(withDuration: 0.8) {
            switch distance {
            case .unknown:
                self.view.backgroundColor = UIColor.gray
                
            case .far:
                self.view.backgroundColor = UIColor.blue
                
            case .near:
                self.view.backgroundColor = UIColor.orange
                
            case .immediate:
                self.view.backgroundColor = UIColor.red
            }
        }
    }
    
    struct Point {
        let position: (xCoord: Double, yCoord: Double, zCoord: Double?)
        let distance: Double
        
        init(position: (xCoord: Double, yCoord: Double, zCoord: Double?),  distance: Double) {
            self.position = position
            self.distance = distance
        }
    }
    
    
}


//class ViewController: UIViewController, CBCentralManagerDelegate, CBPeripheralDelegate {
//    
//    var centralManager: CBCentralManager!
//
//    
//    override func viewDidLoad() {
//        super.viewDidLoad()
//        // Do any additional setup after loading the view, typically from a nib.
//        centralManager = CBCentralManager(delegate: self, queue: nil)
//    }
//
//    override func didReceiveMemoryWarning() {
//        super.didReceiveMemoryWarning()
//        // Dispose of any resources that can be recreated.
//    }
//    
//    
//    // MARK: Actions
//    
//    @IBAction func scanBle(_ sender: UIButton) {
//        
//    }
//    
//    
//    
//    func centralManagerDidUpdateState(_ central: CBCentralManager) {
//        if central.state == CBManagerState.poweredOn {
//            central.scanForPeripherals(withServices: nil, options: nil)
//        } else {
//            print("Bluetooth not available.")
//        }
//        
//    }
//    
//    
//    
//    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
//        
//        let id = peripheral.value(forKey: "identifier")
//        let name = peripheral.name
//        var uuid = ""
//
//
////        if let tmpuuid = advertisementData["kCBAdvDataServiceUUIDs"] {
////            uuid = tmpuuid
////        }
//        
//        print("name : \(name ?? ""), ID : \(id ?? ""), uuids : \(uuid)")
//        print("peripheral : \(peripheral), advertisementData: \(advertisementData), RSSI : \(RSSI)" )
//        
//        for (key, value) in advertisementData {
//            print("\(key) : \(value)")
//        }
//        
//        
//    }
//    
//    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
////        peripheral.discoverServices(nil)
//    }
//    
//    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
////        for service in peripheral.services! {
////            let thisService = service as CBService
////            
////            if service.uuid == BEAN_SERVICE_UUID {
////                peripheral.discoverCharacteristics(nil, for: thisService)
////            }
////            
////        }
//    }
//
//    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
////        for characteristic in service.characteristics! {
////            let thisCharacteristic = characteristic as CBCharacteristic
////            
////            if thisCharacteristic.uuid == BEAN_SCRATCH_UUID {
////                self.peripheral.setNotifyValue(true, for: thisCharacteristic)
////            }
////        }
//    }
//    
//    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
////        var count:UInt32 = 0
////        
////        if characteristic.uuid == BEAN_SCRATCH_UUID {
////            characteristic.value!.
////            
////            
////        }
//    }
//    
//}

