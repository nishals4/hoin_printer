package com.example.hoin_printer

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.printer/bluetooth"
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var discoveredDevices = mutableListOf<Map<String, String>>()
    private var bluetoothSocket: BluetoothSocket? = null
    private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    // NEW: We declare the method channel globally so Android can "call" Flutter
    private lateinit var methodChannel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bluetoothManager.adapter

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startInAppScan" -> {
                    startNativeScan()
                    result.success(true) // Acknowledge scan started immediately
                }
                "connectInApp" -> { val address = call.argument<String>("address"); if (address != null) connectToPrinterDevice(address, result) else result.error("NULL", "No address", null) }
                "disconnectInApp" -> disconnectPrinterDevice(result)
                "sendRawTSPL" -> { val data = call.argument<String>("data"); if (data != null) sendDataStream(data, result) else result.error("NULL", "No data", null) }
                "printBitmapTSPL" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val width = call.argument<Int>("width") ?: 576
                    val height = call.argument<Int>("height") ?: 408
                    val widthMm = call.argument<Int>("widthMm") ?: 76
                    val heightMm = call.argument<Int>("heightMm") ?: 51
                    val gapMm = call.argument<Int>("gapMm") ?: 3
                    val qty = call.argument<Int>("qty") ?: 1

                    if (bytes != null) {
                        printBitmapImage(bytes, width, height, widthMm, heightMm, gapMm, qty, result)
                    } else {
                        result.error("NULL_BYTES", "Pixel array empty", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startNativeScan() {
        discoveredDevices.clear()
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }
        registerReceiver(receiver, filter)
        bluetoothAdapter?.startDiscovery()
    }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                BluetoothDevice.ACTION_FOUND -> {
                    val device: BluetoothDevice? = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                    device?.let {
                        val name = it.name ?: "Generic Printer"
                        val address = it.address
                        if (!discoveredDevices.any { d -> d["address"] == address }) {
                            val deviceMap = mapOf("name" to name, "address" to address)
                            discoveredDevices.add(deviceMap)

                            // NEW: Instantly stream the newly found device up to Flutter UI
                            runOnUiThread {
                                methodChannel.invokeMethod("onDeviceFound", deviceMap)
                            }
                        }
                    }
                }
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                    try { unregisterReceiver(this) } catch (e: Exception) {}

                    // NEW: Tell Flutter the scanning period is officially over
                    runOnUiThread {
                        methodChannel.invokeMethod("onScanFinished", null)
                    }
                }
            }
        }
    }

    private fun connectToPrinterDevice(address: String, result: MethodChannel.Result) {
        bluetoothAdapter?.cancelDiscovery()
        val device = bluetoothAdapter?.getRemoteDevice(address)
        Thread {
            try {
                if (device?.bondState == BluetoothDevice.BOND_NONE) device.createBond()
                bluetoothSocket = device?.createRfcommSocketToServiceRecord(SPP_UUID)
                bluetoothSocket?.connect()
                runOnUiThread { result.success(true) }
            } catch (e: IOException) {
                try { bluetoothSocket?.close() } catch (ex: Exception) {}
                runOnUiThread { result.success(false) }
            }
        }.start()
    }

    private fun disconnectPrinterDevice(result: MethodChannel.Result) {
        try { bluetoothSocket?.close(); result.success(true) } catch (e: IOException) { result.error("ERR", e.message, null) }
    }

    private fun sendDataStream(data: String, result: MethodChannel.Result) {
        if (bluetoothSocket == null || !bluetoothSocket!!.isConnected) { result.error("CLOSED", "No pipe", null); return }
        Thread {
            try {
                bluetoothSocket!!.outputStream.write(data.toByteArray(Charsets.UTF_8))
                bluetoothSocket!!.outputStream.flush()
                runOnUiThread { result.success(true) }
            } catch (e: IOException) { runOnUiThread { result.error("ERR", e.message, null) } }
        }.start()
    }

    private fun printBitmapImage(pixels: ByteArray, width: Int, height: Int, widthMm: Int, heightMm: Int, gapMm: Int, qty: Int, result: MethodChannel.Result) {
        if (bluetoothSocket == null || !bluetoothSocket!!.isConnected) {
            result.error("CLOSED", "Socket connection dead", null)
            return
        }
        Thread {
            try {
                val out = bluetoothSocket!!.outputStream
                val bytesPerLine = (width + 7) / 8

                val header = "SIZE $widthMm mm, $heightMm mm\r\nGAP $gapMm mm, 0 mm\r\nREFERENCE 0,0\r\nDIRECTION 1\r\nCLS\r\nBITMAP 0,0,$bytesPerLine,$height,0,"
                out.write(header.toByteArray(Charsets.US_ASCII))
                out.write(pixels)

                val footer = "\r\nPRINT $qty,1\r\n"
                out.write(footer.toByteArray(Charsets.US_ASCII))
                out.write("CLS\r\n".toByteArray(Charsets.US_ASCII))
                out.write("SET TEAR ON\r\n".toByteArray(Charsets.US_ASCII))
                out.flush()
                runOnUiThread { result.success(true) }
            } catch (e: IOException) {
                runOnUiThread { result.error("WRITE_ERR", e.message, null) }
            }
        }.start()
    }
}