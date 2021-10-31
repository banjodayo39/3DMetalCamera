//
//  RotationOperation.swift
//  MetalTest2
//
//  Created by Dayo Banjo on 10/30/21.
//


import UIKit

public enum Rotation {
    case degree90
    case degree90_flip
    case degree180
    case degree270
    
    func generateVertices(_ size: CGSize) -> [BasicVertex] {
        let vertices: [BasicVertex]
        let w = size.width
        let h = size.height
        
        switch self {
            case .degree90:
                vertices = [
                    BasicVertex(pos: [0, 0, 0], normal: [0, 0, 0], color: [0, 0, 0, 0], tex: [0, 1]),
                    BasicVertex(pos: [1, 0, 0], normal: [0, 0, 0], color: [0, 0, 0, 0], tex: [0, 0]),
                    BasicVertex(pos: [0, 1, 0], normal: [0, 0, 0], color: [0, 0, 0, 0], tex: [1, 1]),
                    BasicVertex(pos: [1, 1, 0], normal: [0, 0, 0], color: [0, 0, 0, 0], tex: [1, 0])
                ]
            case .degree90_flip:
                vertices = [
//                    Vertex(position: CGPoint(x: 0 , y: 0), textCoord: CGPoint(x: 0, y: 0)),
//                    Vertex(position: CGPoint(x: w , y: 0), textCoord: CGPoint(x: 0, y: 1)),
//                    Vertex(position: CGPoint(x: 0 , y: h), textCoord: CGPoint(x: 1, y: 0)),
//                    Vertex(position: CGPoint(x: w , y: h), textCoord: CGPoint(x: 1, y: 1)),
                ]
            case .degree180:
                vertices = [
//                    Vertex(position: CGPoint(x: 0 , y: 0), textCoord: CGPoint(x: 1, y: 1)),
//                    Vertex(position: CGPoint(x: w , y: 0), textCoord: CGPoint(x: 0, y: 1)),
//                    Vertex(position: CGPoint(x: 0 , y: h), textCoord: CGPoint(x: 1, y: 0)),
//                    Vertex(position: CGPoint(x: w , y: h), textCoord: CGPoint(x: 0, y: 0)),
                ]
            case .degree270:
                vertices = [
//                    Vertex(position: CGPoint(x: 0 , y: 0), textCoord: CGPoint(x: 1, y: 0)),
//                    Vertex(position: CGPoint(x: w , y: 0), textCoord: CGPoint(x: 1, y: 1)),
//                    Vertex(position: CGPoint(x: 0 , y: h), textCoord: CGPoint(x: 0, y: 0)),
//                    Vertex(position: CGPoint(x: w , y: h), textCoord: CGPoint(x: 0, y: 1)),
                ]
        }
        
        return vertices
    }
}

public class RotationOperation: OperationChain {
    public let targets = TargetContainer<OperationChain>()
    
    private let rotation: Rotation
    private let size: CGSize
    
    private var pipelineState: MTLRenderPipelineState!
    private var render_target_vertex: MTLBuffer!
    private var render_target_uniform: MTLBuffer!
    
    private let textureInputSemaphore = DispatchSemaphore(value:1)
    
    var device : MTLDevice!
    
    public init(_ rotation: Rotation, _ size: CGSize = CGSize(width: 720, height: 1280)) {
        self.rotation = rotation
        self.size = size
        
        device = MTLCreateSystemDefaultDevice()!
        setup()
    }
    
    private func setup() {
        
        setupTargetUniforms()
        setupPiplineState()
        
    }
    
    private func setupTargetUniforms() {
        render_target_vertex = sharedMetalRenderingDevice.makeRenderVertexBuffer(rotation.generateVertices(size))
        render_target_uniform = sharedMetalRenderingDevice.makeRenderUniformBuffer(size)
    }
    
    // FIXME: Need to refactoring this. There are a lot of same functions in library.
    private func setupPiplineState(_ colorPixelFormat: MTLPixelFormat = .bgra8Unorm) {
        do {
            let rpd = try sharedMetalRenderingDevice.generateRenderPipelineDescriptor("vertex_render_target", "fragment_render_target", colorPixelFormat)
            pipelineState = try sharedMetalRenderingDevice.device.makeRenderPipelineState(descriptor: rpd)
        } catch {
            debugPrint(error)
        }
    }
    
    public func newTextureAvailable(_ texture: Texture) {
        let _ = textureInputSemaphore.wait(timeout:DispatchTime.distantFuture)
        defer {
            textureInputSemaphore.signal()
        }
        
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        let attachment = renderPassDescriptor.colorAttachments[0]
        attachment?.clearColor = MTLClearColorMake(1, 0, 0, 1)
        attachment?.texture = texture.mtlTexture
        attachment?.loadAction = .clear
        attachment?.storeAction = .store
        
        let commandBuffer = sharedMetalRenderingDevice.commandQueue.makeCommandBuffer()
        let commandEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        
        commandEncoder?.setRenderPipelineState(pipelineState)
        
        commandEncoder?.setVertexBuffer(render_target_vertex, offset: 0, index: 0)
        commandEncoder?.setVertexBuffer(render_target_uniform, offset: 0, index: 1)
        commandEncoder?.setFragmentTexture(texture.mtlTexture, index: 0)
        commandEncoder?.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        commandEncoder?.endEncoding()
        commandBuffer?.commit()
        
        textureInputSemaphore.signal()
        operationFinished(texture)
        let _ = textureInputSemaphore.wait(timeout:DispatchTime.distantFuture)
    }
}


import UIKit
import Metal

public let sharedMetalRenderingDevice = MetalRenderingDevice()

public class MetalRenderingDevice {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    
    init() {
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Could not create Metal Device") }
        self.device = device
        
        guard let queue = self.device.makeCommandQueue() else { fatalError("Could not create command queue") }
        self.commandQueue = queue
    }
    
    func generateRenderPipelineDescriptor(_ vertexFuncName: String, _ fragmentFuncName: String, _ colorPixelFormat: MTLPixelFormat = .bgra8Unorm) throws -> MTLRenderPipelineDescriptor {
        let framework = Bundle(for: MetalCamera2.self)
        let resource = framework.path(forResource: "default", ofType: "metallib")!
        print("The respurces is \(resource)")
        let library = try self.device.makeLibrary(filepath: resource)
        
        let vertex_func = library.makeFunction(name: vertexFuncName)
        let fragment_func = library.makeFunction(name: fragmentFuncName)
        let rpd = MTLRenderPipelineDescriptor()
        rpd.vertexFunction = vertex_func
        rpd.fragmentFunction = fragment_func
        rpd.colorAttachments[0].pixelFormat = colorPixelFormat
        
        return rpd
    }
    
    func makeRenderVertexBuffer(_ origin: CGPoint = .zero, size: CGSize) -> MTLBuffer? {
        let w = size.width, h = size.height
        let vertices = [
            BasicVertex(pos: [0, 0, 0], normal: [0,0,0], color: [0,0,0], tex: [0,0]),
            BasicVertex(pos: [1, 0, 0], normal: [0,0,0], color: [0,0,0], tex: [1,0]),
            BasicVertex(pos: [0, 1, 0], normal: [0,0,0], color: [0,0,0], tex: [0,1]),
            BasicVertex(pos: [1, 1, 0], normal: [0,0,0], color: [0,0,0], tex: [1,1])
        ]
        return makeRenderVertexBuffer(vertices)
    }
    
    func makeRenderVertexBuffer(_ vertices: [BasicVertex]) -> MTLBuffer? {
        return self.device.makeBuffer(bytes: vertices, length: MemoryLayout<BasicVertex>.stride * vertices.count, options: .cpuCacheModeWriteCombined)        
    }
    
    func makeRenderUniformBuffer(_ size: CGSize) -> MTLBuffer? {
        let metrix = Matrix.identity
        metrix.scaling(x: 2 / Float(size.width), y: -2 / Float(size.height), z: 1)
        metrix.translation(x: -1, y: 1, z: 0)
        return self.device.makeBuffer(bytes: metrix.m, length: MemoryLayout<Float>.size * 16, options: [])
    }
}

class Matrix {
    
    private(set) var m: [Float]
    
    static var identity = Matrix()
    
    private init() {
        m = [1, 0, 0, 0,
             0, 1, 0, 0,
             0, 0, 1, 0,
             0, 0, 0, 1
        ]
    }
    
    @discardableResult
    func translation(x: Float, y: Float, z: Float) -> Matrix {
        m[12] = x
        m[13] = y
        m[14] = z
        return self
    }
    
    @discardableResult
    func scaling(x: Float, y: Float, z: Float)  -> Matrix  {
        m[0] = x
        m[5] = y
        m[10] = z
        return self
    }
}
