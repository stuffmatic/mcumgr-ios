/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

public class McuMgrResponse: CBORMappable, CustomStringConvertible, CustomDebugStringConvertible {
    
    //*******************************************************************************************
    // MARK: Value Mapping
    //*******************************************************************************************
    
    /// Every McuMgrResponse will contain a return code value. If the original response packet
    /// does not contain a "rc", the success value of 0 is assumed.
    public var rc: UInt = 0
    
    //*******************************************************************************************
    // MARK: Response Properties
    //*******************************************************************************************

    /// The transport scheme used by the transporter. This is used to determine how to parse the
    /// raw packet.
    public var scheme: McuMgrScheme!
    
    /// The response's raw packet data. For CoAP transport schemes, this will include the CoAP
    /// header.
    public var data: Data?
    
    /// The 8-byte McuMgrHeader included in the response
    public var header: McuMgrHeader!
    
    /// The CBOR payload from
    public var payload: CBOR?
    
    /// The raw McuMgrResponse payload
    public var payloadData: Data?
    
    /// The repsponse's return code obtained from the payload. If no return code is explicitly
    /// stated, OK (0) is assumed.
    public var returnCode: McuMgrReturnCode! = .ok
    
    /// The CoAP Response code for CoAP based transport schemes. For non-CoAP transport schemes
    /// this value will always be 0
    public var coapCode: Int = 0
    
    /// String representation of the response.
    public var description: String {
        return payload?.description ?? "nil"
    }
    
    /// String representation of the response.
    public var debugDescription: String {
        return "Header: \(self.header!), Payload: \(payload?.description ?? "nil")"
    }
    
    //*******************************************************************************************
    // MARK: Initializers
    //*******************************************************************************************
    
    public required init(cbor: CBOR?) throws {
        try super.init(cbor: cbor)
        if case let CBOR.unsignedInt(rc)? = cbor?["rc"] {
            self.rc = rc
        }
    }
    
    //*******************************************************************************************
    // MARK: Functions
    //*******************************************************************************************
    
    public func isSuccess() -> Bool {
        return returnCode.isSuccess()
    }
    
    //*******************************************************************************************
    // MARK: Static Builders
    //*******************************************************************************************
    
    /// Build an McuMgrResponse.
    ///
    /// This method will parse the raw packet data according to the transport scheme to obtain
    /// the header, payload, and return code. After getting the CBOR payload. An object of type
    /// <T> will be initialized which will map the CBOR payload values to the values in the
    /// object.
    ///
    /// - parameter scheme: the transport scheme of the transporter
    /// - parameter data: The response's raw packet data
    /// - parameter coapPaylaod: (Optional) payload for CoAP transport schemes
    /// - parameter coapCode: (Optional) CoAP response code
    ///
    /// - returns: The McuMgrResponse on success or nil on failure
    public static func buildResponse<T: McuMgrResponse>(scheme: McuMgrScheme, data: Data?, coapPayload: Data? = nil, coapCode: Int = 0) throws -> T {
        guard let data = data else {
            throw McuMgrResponseParseError.invalidDataSize
        }
        if data.count < McuMgrHeader.HEADER_LENGTH {
            throw McuMgrResponseParseError.invalidDataSize
        }
        
        var payloadData: Data?
        var payload: CBOR?
        var header: McuMgrHeader?
        
        // Get the header and payload based on the transport scheme. CoAP schemes put the header
        // in the CBOR payload while standard schemes prepend the header to the CBOR payload.
        if scheme.isCoap() {
            guard let coapPayload = coapPayload else {
                throw McuMgrResponseParseError.invalidDataSize
            }
            payloadData = coapPayload
            // Parse the raw payload into CBOR
            payload = try CBOR.decode([UInt8](coapPayload))
            // Get the header from the CBOR
            if case let CBOR.byteString(rawHeader)? = payload?["_h"] {
                header = try McuMgrHeader(data: Data(rawHeader))
            } else {
                throw McuMgrResponseParseError.invalidPayload
            }
        } else {
            // Parse the header
            header = try McuMgrHeader(data: data)
            // Get header and payload from raw data
            payloadData = data.subdata(in: McuMgrHeader.HEADER_LENGTH..<data.count)
            if payloadData != nil {
                // Parse CBOR from raw payload
                payload = try CBOR.decode([UInt8](payloadData!))
            } else {
                payload = nil
            }
        }
        
        // Init the response with the CBOR payload. This will also map the CBOR values to object values
        let response = try T(cbor: payload)
        
        // Set remaining properties
        response.payloadData = payloadData
        response.payload = payload
        response.header = header
        response.scheme = scheme
        response.data = data
        response.returnCode = McuMgrReturnCode(rawValue: response.rc)
        response.coapCode = coapCode
        
        return response
    }
    
    /// Build an McuMgrResponse for standard transport schemes (i.e. non-CoAP).
    ///
    /// This method will parse the raw packet data according to the transport scheme to obtain
    /// the header, payload, and return code. After getting the CBOR payload. An object of type
    /// <T> will be initialized which will map the CBOR payload values to the values in the
    /// object.
    ///
    /// - parameter scheme: the transport scheme of the transporter
    /// - parameter data: The response's raw packet data
    ///
    /// - returns: The McuMgrResponse on success or nil on failure
    public static func buildResponse<T: McuMgrResponse>(scheme: McuMgrScheme, data: Data?) throws -> T {
        return try buildResponse(scheme: scheme, data: data, coapPayload: nil, coapCode: 0)
    }
    
    /// Build a McuMgrResponse for CoAP transport schemes to return to the McuManager
    ///
    /// This method will parse the raw packet data according to the transport scheme to obtain
    /// the header, payload, and return code. After getting the CBOR payload. An object of type
    /// <T> will be initialized which will map the CBOR payload values to the values in the
    /// object.
    ///
    /// - parameter scheme: The transport scheme of the transporter
    /// - parameter data: The response's raw packet data
    /// - parameter coapPayload: The CoAP payload of the response
    /// - parameter codeClass: The CoAP response code class
    /// - parameter codeDetail: The CoAP response code detail
    ///
    /// - returns: The McuMgrResponse on success or nil on failure
    public static func buildCoapResponse<T: McuMgrResponse>(scheme: McuMgrScheme, data: Data, coapPayload: Data, codeClass: Int, codeDetail: Int) throws -> T? {
        return try buildResponse(scheme: scheme, data: data, coapPayload: coapPayload, coapCode: (codeClass * 100 + codeDetail))
    }
    
    //*******************************************************************************************
    // MARK: Utilities
    //*******************************************************************************************
    
    /// Gets the expected length of the entire respose from the length field in the
    /// McuMgrHeader. The return value includes the 8-byte McuMgr header.
    ///
    /// - parameter scheme: The transport scheme (Must be BLE to use this function)
    ///
    /// - returns: The expected length of the header or nil on error
    public static func getExpectedLength(scheme: McuMgrScheme, responseData: Data) -> Int? {
        if scheme.isCoap() {
            return nil // TODO
        } else {
            if let header = try? McuMgrHeader(data: responseData) {
                return Int(header.length) + McuMgrHeader.HEADER_LENGTH
            } else {
                return nil
            }
        }
    }
}

//***********************************************************************************************
// MARK: Errors
//***********************************************************************************************

public enum McuMgrResponseParseError: Error {
    case invalidDataSize
    case invalidPayload
}

//***********************************************************************************************
// MARK: Default Responses
//***********************************************************************************************

public class McuMgrEchoResponse: McuMgrResponse {
    
    /// Echo response
    public var response: String?
    
    public required init(cbor: CBOR?) throws {
        try super.init(cbor: cbor)
        if case let CBOR.utf8String(response)? = cbor?["r"] {
            self.response = response
        }
    }
}

public class McuMgrTaskStatResponse: McuMgrResponse {
    
    /// A map of task names to task statistics
    public var tasks: [String:TaskStatistics]?
    
    public required init(cbor: CBOR?) throws {
        try super.init(cbor: cbor)
        if case let CBOR.map(tasks)? = cbor?["tasks"] {
            self.tasks = try CBOR.toObjectMap(map: tasks)
        }
    }
    
    public class TaskStatistics: CBORMappable {
        
        /// The task's priority
        public var priority: UInt!
        /// The task's ID
        public var taskId: UInt!
        /// The task's state
        public var state: UInt!
        /// The actual size of the task's stack that is being used
        public var stackUse: UInt!
        /// The size of the task's stack
        public var stackSize: UInt!
        /// The number of times the task has switched context
        public var contextSwitchCount: UInt!
        /// The time (ms) that the task has been running
        public var runtime: UInt!
        /// The last sanity checking with the sanity task
        public var lastCheckin: UInt!
        /// The next sanity checkin
        public var nextCheckin: UInt!
        
        public required init(cbor: CBOR?) throws {
            try super.init(cbor: cbor)
            if case let CBOR.unsignedInt(priority)? = cbor?["prio"] {self.priority = priority}
            if case let CBOR.unsignedInt(taskId)? = cbor?["tid"] {self.taskId = taskId}
            if case let CBOR.unsignedInt(state)? = cbor?["state"] {self.state = state}
            if case let CBOR.unsignedInt(stackUse)? = cbor?["stkuse"] {self.stackUse = stackUse}
            if case let CBOR.unsignedInt(stackSize)? = cbor?["stksiz"] {self.stackSize = stackSize}
            if case let CBOR.unsignedInt(contextSwitchCount)? = cbor?["cswcnt"] {self.contextSwitchCount = contextSwitchCount}
            if case let CBOR.unsignedInt(runtime)? = cbor?["runtime"] {self.runtime = runtime}
            if case let CBOR.unsignedInt(lastCheckin)? = cbor?["last_checkin"] {self.lastCheckin = lastCheckin}
            if case let CBOR.unsignedInt(nextCheckin)? = cbor?["next_checkin"] {self.nextCheckin = nextCheckin}
        }
    }
}



//***********************************************************************************************
// MARK: Image Responses
//***********************************************************************************************

public class McuMgrImageStateResponse: McuMgrResponse {
    
    /// The image slots on the device. This may contain one or two values, depending on whether
    /// there is an image loaded in slot 1
    public var images: [ImageSlot]?
    /// Whether the bootloader is configured to use a split image setup
    public var splitStatus: UInt?
    
    public required init(cbor: CBOR?) throws {
        try super.init(cbor: cbor)
        if case let CBOR.unsignedInt(splitStatus)? = cbor?["splitStatus"] {
            self.splitStatus = splitStatus
        }
        if case let CBOR.array(images)? = cbor?["images"] {
            self.images = try CBOR.toObjectArray(array: images)
        }
    }
    
    public class ImageSlot: CBORMappable {
        /// The (zero) index of this image slot
        public var slot: UInt!
        /// The verison of the image
        public var version: String!
        /// The sha256 hash of the image
        public var hash: [UInt8]!
        /// Bootable flag
        public var bootable: Bool!
        /// Pending flag. A pending image will be booted into on reset.
        public var pending: Bool!
        /// Confired flag. A confirmed image will always be booted into (unless another image is
        /// pending.
        public var confirmed: Bool!
        /// Active flag. Set if the image in this slot is active
        public var active: Bool!
        /// Permanent flag. Set if this image is permanent
        public var permanent: Bool!
        
        public required init(cbor: CBOR?) throws {
            try super.init(cbor: cbor)
            if case let CBOR.unsignedInt(slot)? = cbor?["slot"] {self.slot = slot}
            if case let CBOR.utf8String(version)? = cbor?["version"] {self.version = version}
            if case let CBOR.byteString(hash)? = cbor?["hash"] {self.hash = hash}
            if case let CBOR.boolean(bootable)? = cbor?["bootable"] {self.bootable = bootable}
            if case let CBOR.boolean(pending)? = cbor?["pending"] {self.pending = pending}
            if case let CBOR.boolean(confirmed)? = cbor?["confirmed"] {self.confirmed = confirmed}
            if case let CBOR.boolean(active)? = cbor?["active"] {self.active = active}
            if case let CBOR.boolean(permanent)? = cbor?["permanent"] {self.permanent = permanent}
        }
    }
}

public class McuMgrUploadResponse: McuMgrResponse {
    
    /// Offset to send the next packet of image data from
    public var off: UInt?
    
    public required init(cbor: CBOR?) throws {
        try super.init(cbor: cbor)
        if case let CBOR.unsignedInt(off)? = cbor?["off"] {self.off = off}
    }
}

//***********************************************************************************************
// MARK: Logs Responses
//***********************************************************************************************

//***********************************************************************************************
// MARK: Stats Responses
//***********************************************************************************************

//***********************************************************************************************
// MARK: Config Responses
//***********************************************************************************************