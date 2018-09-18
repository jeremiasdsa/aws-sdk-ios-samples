/*
* Copyright 2010-2018 Amazon.com, Inc. or its affiliates. All Rights Reserved.
*
* Licensed under the Apache License, Version 2.0 (the "License").
* You may not use this file except in compliance with the License.
* A copy of the License is located at
*
*  http://aws.amazon.com/apache2.0
*
* or in the "license" file accompanying this file. This file is distributed
* on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
* express or implied. See the License for the specific language governing
* permissions and limitations under the License.
*/

import UIKit
import AWSIoT

class ConnectionViewController: UIViewController, UITextViewDelegate {

    @IBOutlet weak var subscribeLabel: UILabel!
    @IBOutlet weak var activityIndicatorView: UIActivityIndicatorView!
    @IBOutlet weak var logTextView: UITextView!
    @IBOutlet weak var lampImage: UIImageView!
    
    @IBOutlet weak var statusConectImage: UIImageView!
    var connected = false;
    var configurationViewController : UIViewController!;

    @IBOutlet weak var btnSwitch: UISwitch!
    
    var iotDataManager: AWSIoTDataManager!;
    var iotManager: AWSIoTManager!;
    var iot: AWSIoT!

    @IBAction func connectButtonPressed(_ sender: UIButton) {

        let tabBarViewController = tabBarController as! IoTSampleTabBarController

        sender.isEnabled = false

        func mqttEventCallback( _ status: AWSIoTMQTTStatus )
        {
            DispatchQueue.main.async {
                print("connection status = \(status.rawValue)")
                switch(status)
                {
                    case .connecting:
                        tabBarViewController.mqttStatus = "Connecting..."
                        print( tabBarViewController.mqttStatus )
                        self.logTextView.text = tabBarViewController.mqttStatus
                    
                        self.statusConectImage.backgroundColor = UIColor.yellow

                    case .connected:
                        tabBarViewController.mqttStatus = "Connected"
                        print( tabBarViewController.mqttStatus )
                        sender.setTitle( "Disconnect", for:UIControlState())
                        self.activityIndicatorView.stopAnimating()
                        self.connected = true
                        sender.isEnabled = true
                        let uuid = UUID().uuidString;
                        let defaults = UserDefaults.standard
                        let certificateId = defaults.string( forKey: "certificateId")

                        self.logTextView.text = "Using certificate:\n\(certificateId!)\n\n\nClient ID:\n\(uuid)"

                        self.statusConectImage.backgroundColor = UIColor.green
                        
                        tabBarViewController.viewControllers = [ self ]
                    

                    case .disconnected:
                        tabBarViewController.mqttStatus = "Disconnected"
                        print( tabBarViewController.mqttStatus )
                        self.activityIndicatorView.stopAnimating()
                        self.logTextView.text = nil
                    
                        self.statusConectImage.backgroundColor = UIColor.red

                    case .connectionRefused:
                        tabBarViewController.mqttStatus = "Connection Refused"
                        print( tabBarViewController.mqttStatus )
                        self.activityIndicatorView.stopAnimating()
                        self.logTextView.text = tabBarViewController.mqttStatus

                    case .connectionError:
                        tabBarViewController.mqttStatus = "Connection Error"
                        print( tabBarViewController.mqttStatus )
                        self.activityIndicatorView.stopAnimating()
                        self.logTextView.text = tabBarViewController.mqttStatus

                    case .protocolError:
                        tabBarViewController.mqttStatus = "Protocol Error"
                        print( tabBarViewController.mqttStatus )
                        self.activityIndicatorView.stopAnimating()
                        self.logTextView.text = tabBarViewController.mqttStatus

                    default:
                        tabBarViewController.mqttStatus = "Unknown State"
                        print("unknown state: \(status.rawValue)")
                        self.activityIndicatorView.stopAnimating()
                        self.logTextView.text = tabBarViewController.mqttStatus
                }
                
                NotificationCenter.default.post( name: Notification.Name(rawValue: "connectionStatusChanged"), object: self )
            }
        }

        if (connected == false)
        {
            activityIndicatorView.startAnimating()

            let defaults = UserDefaults.standard
            var certificateId = defaults.string( forKey: "certificateId")

            if (certificateId == nil)
            {
                DispatchQueue.main.async {
                    self.logTextView.text = "No identity available, searching bundle..."
                }
                
                // No certificate ID has been stored in the user defaults; check to see if any .p12 files
                // exist in the bundle.
                let myBundle = Bundle.main
                let myImages = myBundle.paths(forResourcesOfType: "p12" as String, inDirectory:nil)
                let uuid = UUID().uuidString;
                
                if (myImages.count > 0) {
                    // At least one PKCS12 file exists in the bundle.  Attempt to load the first one
                    // into the keychain (the others are ignored), and set the certificate ID in the
                    // user defaults as the filename.  If the PKCS12 file requires a passphrase,
                    // you'll need to provide that here; this code is written to expect that the
                    // PKCS12 file will not have a passphrase.
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: myImages[0])) {
                        DispatchQueue.main.async {
                            self.logTextView.text = "found identity \(myImages[0]), importing..."
                        }
                        if AWSIoTManager.importIdentity( fromPKCS12Data: data, passPhrase:"", certificateId:myImages[0]) {
                            // Set the certificate ID and ARN values to indicate that we have imported
                            // our identity from the PKCS12 file in the bundle.
                            defaults.set(myImages[0], forKey:"certificateId")
                            defaults.set("from-bundle", forKey:"certificateArn")
                            DispatchQueue.main.async {
                                self.logTextView.text = "Using certificate: \(myImages[0]))"
                                self.iotDataManager.connect( withClientId: uuid, cleanSession:true, certificateId:myImages[0], statusCallback: mqttEventCallback)
                            }
                        }
                    }
                }
                
                certificateId = defaults.string( forKey: "certificateId")
                if (certificateId == nil) {
                    DispatchQueue.main.async {
                        self.logTextView.text = "No identity found in bundle, creating one..."
                    }

                    // Now create and store the certificate ID in NSUserDefaults
                    let csrDictionary = [ "commonName":CertificateSigningRequestCommonName, "countryName":CertificateSigningRequestCountryName, "organizationName":CertificateSigningRequestOrganizationName, "organizationalUnitName":CertificateSigningRequestOrganizationalUnitName ]

                    self.iotManager.createKeysAndCertificate(fromCsr: csrDictionary, callback: {  (response ) -> Void in
                        if (response != nil)
                        {
                            defaults.set(response?.certificateId, forKey:"certificateId")
                            defaults.set(response?.certificateArn, forKey:"certificateArn")
                            certificateId = response?.certificateId
                            print("response: [\(String(describing: response))]")

                            let attachPrincipalPolicyRequest = AWSIoTAttachPrincipalPolicyRequest()
                            attachPrincipalPolicyRequest?.policyName = PolicyName
                            attachPrincipalPolicyRequest?.principal = response?.certificateArn
                            
                            // Attach the policy to the certificate
                            self.iot.attachPrincipalPolicy(attachPrincipalPolicyRequest!).continueWith (block: { (task) -> AnyObject? in
                                if let error = task.error {
                                    print("failed: [\(error)]")
                                }
                                print("result: [\(String(describing: task.result))]")
                                
                                // Connect to the AWS IoT platform
                                if (task.error == nil)
                                {
                                    DispatchQueue.main.asyncAfter(deadline: .now()+2, execute: {
                                        self.logTextView.text = "Using certificate: \(certificateId!)"
                                        self.iotDataManager.connect( withClientId: uuid, cleanSession:true, certificateId:certificateId!, statusCallback: mqttEventCallback)

                                    })
                                }
                                return nil
                            })
                        }
                        else
                        {
                            DispatchQueue.main.async {
                                sender.isEnabled = true
                                self.activityIndicatorView.stopAnimating()
                                self.logTextView.text = "Unable to create keys and/or certificate, check values in Constants.swift"
                            }
                        }
                    } )
                }
            }
            else
            {
                let uuid = UUID().uuidString;

                // Connect to the AWS IoT service
                iotDataManager.connect( withClientId: uuid, cleanSession:true, certificateId:certificateId!, statusCallback: mqttEventCallback)
            }
        }
        else
        {
            activityIndicatorView.startAnimating()
            logTextView.text = "Disconnecting..."

            DispatchQueue.global(qos: DispatchQoS.QoSClass.default).async {
                self.iotDataManager.disconnect();
                DispatchQueue.main.async {
                    self.activityIndicatorView.stopAnimating()
                    self.connected = false
                    sender.setTitle( "Connect", for:UIControlState())
                    sender.isEnabled = true
                    tabBarViewController.viewControllers = [ self, self.configurationViewController ]
                }
            }
        }
    }

    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let tabBarViewController = tabBarController as! IoTSampleTabBarController
     
        configurationViewController = tabBarViewController.viewControllers![1]

        tabBarViewController.viewControllers = [ self, configurationViewController ]
        logTextView.resignFirstResponder()

        
        // Init IOT
        // Set up Cognito
        let credentialsProvider = AWSCognitoCredentialsProvider(regionType: AWSRegion, identityPoolId: CognitoIdentityPoolId)
        let iotEndPoint = AWSEndpoint(urlString: IOT_ENDPOINT)
        
        // Configuration for AWSIoT control plane APIs
        let iotConfiguration = AWSServiceConfiguration(region: AWSRegion, credentialsProvider: credentialsProvider)
        
        // Configuration for AWSIoT data plane APIs
        let iotDataConfiguration = AWSServiceConfiguration(region: AWSRegion,
                                                           endpoint: iotEndPoint,
                                                           credentialsProvider: credentialsProvider)
        AWSServiceManager.default().defaultServiceConfiguration = iotConfiguration
        
        iotManager = AWSIoTManager.default()
        iot = AWSIoT.default()
        
        AWSIoTDataManager.register(with: iotDataConfiguration!, forKey: ASWIoTDataManager)
        iotDataManager = AWSIoTDataManager(forKey: ASWIoTDataManager)
        

    }
    
    @IBAction func subscribePressed(_ sender: Any) {
        _ = subscribing()
    }
    
    
    fileprivate func subscribing() -> Bool {
        return iotDataManager.subscribe(toTopic: topic, qoS: .messageDeliveryAttemptedAtMostOnce, messageCallback: {
            (payload) ->Void in
            let stringValue = NSString(data: payload, encoding: String.Encoding.utf8.rawValue)!
            
            print("received: \(stringValue)")
            
            if (stringValue.isEqual(to:  "{\n" +
                "    gpio: {\n" +
                "        pin: 2,\n" +
                "        state: 0\n" +
                "    }\n" +
                "}")) {
                self.lampImage.image = #imageLiteral(resourceName: "lampOn")
            } else {
                self.lampImage.image = #imageLiteral(resourceName: "lampOff")
            }
            
            DispatchQueue.main.async {
                self.subscribeLabel.text = "\(stringValue)"
            }
        } )
    }
    
    
    @IBAction func switchPressed(_ sender: Any) {
        if self.btnSwitch.isOn {
            iotDataManager.publishString(
                    "{\n" +
                        "    gpio: {\n" +
                        "        pin: 2,\n" +
                        "        state: 0\n" +
                        "    }\n" +
                    "}",
                onTopic: topic,
                qoS:.messageDeliveryAttemptedAtMostOnce)
        } else {
            iotDataManager.publishString(
                    "{\n" +
                        "    gpio: {\n" +
                        "        pin: 2,\n" +
                        "        state: 1\n" +
                        "    }\n" +
                    "}",
                onTopic:topic,
                qoS:.messageDeliveryAttemptedAtMostOnce)
        }
    }
    
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let iotDataManager = AWSIoTDataManager(forKey: ASWIoTDataManager)
        iotDataManager.unsubscribeTopic(topic)
    }
}

