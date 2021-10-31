//
//  ViewController.swift
//  MetalTest2
//
//  Created by Dayo Banjo on 10/30/21.
//

import UIKit
//import MetalKit
import UIKit
import AVFoundation
import MetalKit

class ViewController: UIViewController {

    var camera: MetalCamera2!
    
   
    
    private enum Demo {
        case singleCube
        case singleCubeTextured
        case singleCubeVideo
        case multipleCubesFew
        case multipleCubesMany
        case bunny
    }
    
    var fpsLabel = UILabel()
    private var currentDemoType = Demo.singleCube
    private var renderer: Renderer!
    private var mtkView: MTKView!
    private var examples: Examples!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        mtkView = MTKView(frame: view.bounds, device: MTLCreateSystemDefaultDevice())
    
//        guard let mtkView = view as? MTKView else {
//            print("View of Gameview controller is not an MTKView")
//            return
//        }
        view.addSubview(mtkView)
        guard let renderer = Renderer(mtkView: mtkView) else {
            print("Renderer cannot be initialized")
            return
        }
        self.renderer = renderer
        
        let scale = UIScreen.main.scale
        
        self.renderer.onFrame = { [unowned renderer] in
            self.examples.onRendererFrame()
            
            let size = self.mtkView.bounds.size
            self.fpsLabel.text = "[\(size.width * scale) x \(size.height * scale)], FPS: \(String(format: "%.0f", renderer.fpsCounter.currentFPS))"
        }
        
        mtkView.delegate = renderer
        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        
        // Tap to change the demos
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(onTap))
        tapGesture.numberOfTapsRequired = 1
        mtkView.addGestureRecognizer(tapGesture)
        
        // Class containing several different demo scenes
        examples = Examples(renderer: renderer)
       examples.createPlaneScene(textured: true)
       //examples.createP2()
        setupView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        camera?.startCapture()
       // video?.start()
        
        //        camera.faceRectangle = {[weak self]  faceRect in
        //            print("The face view",faceRect)
        //            self?.imageCompositor.updatePos(faceRect)
        //        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        camera?.stopCapture()
        //video?.stop()
    }
    
    @objc func onTap(_ recognizer: UITapGestureRecognizer) {
        switch currentDemoType {
            
            case .singleCube:
                examples.createSceneSingleCube(textured: true)
                currentDemoType = .singleCubeTextured
                
            case .singleCubeTextured:
                renderer.scene.camera.origin = [0, 0, 7]
                examples.createSceneVideoTextureCube()
                currentDemoType = .singleCubeVideo
                
            case .singleCubeVideo:
                renderer.scene.camera.origin = [0, 0, 7]
                examples.createSceneMultipleCubes(cubeDimension: 1.0, cubeCount: 100)
                currentDemoType = .multipleCubesFew
                
            case .multipleCubesFew:
                renderer.scene.camera.origin = [0, 0, 7]
                examples.createSceneMultipleCubes(cubeDimension: 0.5, cubeCount: 10000)
                currentDemoType = .multipleCubesMany
                
            case .multipleCubesMany:
                renderer.scene.camera.origin = [0, 0, 5]
                examples.createSceneBunny()
                currentDemoType = .bunny
                
            case .bunny:
                examples.createSceneSingleCube(textured: false)
                currentDemoType = .singleCube
        }
    }
        
}





extension ViewController {
    //MARK:- View Setup
    func setupView(){
        guard let camera = try? MetalCamera2(useMic: false) else { return }
        //let rotation90 = RotationOperation(.degree90_flip)

        camera-->examples
        self.camera = camera
    }
    
    //MARK:- Permissions
    func checkPermissions() {
        let cameraAuthStatus =  AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
        switch cameraAuthStatus {
            case .authorized:
                return
            case .denied:
                abort()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler:
                                                { (authorized) in
                                                    if(!authorized){
                                                        abort()
                                                    }
                                                })
            case .restricted:
                abort()
            @unknown default:
                fatalError()
        }
    }
}

